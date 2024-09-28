// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.22;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IGovStakerEscrow} from "../interfaces/IGovStakerEscrow.sol";

contract GovStaker {
    using SafeERC20 for IERC20;

    uint public immutable MAX_STAKE_GROWTH_EPOCHS;
    uint8 public immutable MAX_WEEK_BIT;
    uint public immutable START_TIME;
    uint public immutable EPOCH_LENGTH;
    IERC20 public immutable stakeToken;
    IGovStakerEscrow public immutable ESCROW;

    // Account weight tracking state vars.
    mapping(address account => AccountData data) public accountData;
    mapping(address account => mapping(uint epoch => uint weight)) private accountWeightInEpoch;
    mapping(address account => mapping(uint epoch => uint weight)) public accountToRealizeInEpoch;

    // Global weight tracking state vars.
    uint112 public globalGrowthRate;
    uint16 public globalLastUpdateWeek;
    mapping(uint epoch => uint weight) private globalWeightInEpoch;
    mapping(uint epoch => uint weight) public globalToRealizeInEpoch;

    // Cooldown tracking vars.
    uint public cooldownDuration;
    mapping(address => UserCooldown) public cooldowns;
    uint24 public immutable MAX_COOLDOWN_DURATION = 30 days;

    // Generic token interface.
    uint public totalSupply;
    uint8 public immutable decimals;

    // Permissioned roles
    address public owner;
    mapping(address account => mapping(address caller => ApprovalStatus approvalStatus)) public approvedCaller;
    mapping(address staker => bool approved) public approvedWeightedStaker;

    struct AccountData {
        uint112 realizedStake;  // Amount of stake that has fully realized weight.
        uint112 pendingStake;   // Amount of stake that has not yet fully realized weight.
        uint16 lastUpdateEpoch;  // Week of last sync.

        // One byte member to represent epochs in which an account has pending weight changes.
        // A bit is set to true when the account has a non-zero token balance to be realized in
        // the corresponding epoch. We use this as a "map", allowing us to reduce gas consumption
        // by avoiding unnecessary lookups on epochs which an account has zero pending stake.
        //
        // Example: 01000001
        // The left-most bit represents the final epoch of pendingStake.
        // Therefore, we can see that account has stake updates to process only in epochs 7 and 1.
        uint8 updateEpochsBitmap;
    }

    struct UserCooldown {
        uint104 cooldownEnd;
        uint152 underlyingAmount;
    }

    enum ApprovalStatus {
        None,               // 0. Default value, indicating no approval
        StakeOnly,          // 1. Approved for stake only
        UnstakeOnly,        // 2. Approved for unstake only
        StakeAndUnstake     // 3. Approved for both stake and unstake
    }

    modifier ensureCooldownOff() {
        require(cooldownDuration == 0, "CooldownOn");
        _;
    }

    modifier ensureCooldownOn() {
        require(cooldownDuration != 0, "CooldownOff");
        _;
    }

    event Staked(address indexed account, uint indexed epoch, uint amount);
    event Unstaked(address indexed account, uint amount);
    event ApprovedCallerSet(address indexed account, address indexed caller, ApprovalStatus status);
    event Cooldown(address indexed account, uint amount, uint end);

    /**
        @param _token The token to be staked.
        @param _epoch_length The length of an epoch in seconds.
        @param _max_stake_growth_epochs The number of epochs a stake will grow for.
                            Not including desposit epoch.
        @param _start_time  allows deployer to optionally set a custom start time.
                            useful if needed to line up with epoch count in another system.
                            Passing a value of 0 will start at block.timestamp.
        @param _owner       Owner is able to grant access to stake with max boost.
    */
    constructor(
        address _token, 
        uint _epoch_length,
        uint _max_stake_growth_epochs, 
        uint _start_time, 
        address _owner, 
        IGovStakerEscrow _escrow
    ) {
        owner = _owner;
        stakeToken = IERC20(_token);
        decimals = IERC20Metadata(_token).decimals();
        require(
            _max_stake_growth_epochs > 0 &&
            _max_stake_growth_epochs <= 7,
            "Invalid epochs"
        );
        MAX_STAKE_GROWTH_EPOCHS = _max_stake_growth_epochs;
        MAX_WEEK_BIT = uint8(1 << MAX_STAKE_GROWTH_EPOCHS);
        EPOCH_LENGTH = _epoch_length;
        if (_start_time == 0){
            START_TIME = block.timestamp;
        }
        else {
            require(_start_time <= block.timestamp, "!Past");
            START_TIME = _start_time;
        }
        ESCROW = _escrow;
        cooldownDuration = min(MAX_COOLDOWN_DURATION, EPOCH_LENGTH * MAX_STAKE_GROWTH_EPOCHS);
    }

    /**
        @notice Stake tokens into the staking contract.
        @param _amount Amount of tokens to stake.
    */
    function stake(uint _amount) external returns (uint) {
        return _stake(msg.sender, _amount);
    }

    function stakeFor(address _account, uint _amount) external returns (uint) {
        if (msg.sender != _account) {
            ApprovalStatus status = approvedCaller[_account][msg.sender];
            require(
                status == ApprovalStatus.StakeAndUnstake ||
                status == ApprovalStatus.StakeOnly,
                "!Permission"
            );
        }
        
        return _stake(_account, _amount);
    }

    function _stake(address _account, uint _amount) internal returns (uint) {
        require(_amount < type(uint112).max, "invalid amount");

        // Before going further, let's sync our account and global weights
        uint systemEpoch = getEpoch();
        (AccountData memory acctData, ) = _checkpointAccount(_account, systemEpoch);
        _checkpointGlobal(systemEpoch);

        uint weight = _amount;
        
        acctData.pendingStake += uint112(weight);
        globalGrowthRate += uint112(weight);

        uint realizeEpoch = systemEpoch + MAX_STAKE_GROWTH_EPOCHS;

        accountToRealizeInEpoch[_account][realizeEpoch] += weight;
        globalToRealizeInEpoch[realizeEpoch] += weight;

        acctData.updateEpochsBitmap |= 1; // Use bitwise or to ensure bit is flipped at least weighted position.
        accountData[_account] = acctData;
        totalSupply += _amount;
        
        stakeToken.safeTransferFrom(msg.sender, address(this), uint(_amount));
        emit Staked(_account, systemEpoch, _amount);
        
        return _amount;
    }

    /**
        @notice Unstake tokens from the contract.
        @dev During partial unstake, this will always remove from the least-weighted first.
    */
    function cooldown(uint _amount) external returns (uint) {
        return _cooldown(msg.sender, _amount);
    }

    /**
        @notice Unstake tokens from the contract on behalf of another user.
        @dev During partial unstake, this will always remove from the least-weighted first.
    */
    // function unstakeFor(address _account, uint _amount, address _receiver) external returns (uint) {
    function cooldownFor(address _account, uint _amount) external returns (uint) {
        if (msg.sender != _account) {
            ApprovalStatus status = approvedCaller[_account][msg.sender];
            require(
                status == ApprovalStatus.StakeAndUnstake ||
                status == ApprovalStatus.UnstakeOnly,
                "!Permission"
            );
        }
        return _cooldown(_account, _amount);
    }

    function _cooldown(address _account, uint _amount) internal returns (uint) {
        require(_amount < type(uint112).max, "invalid amount");
        uint systemEpoch = getEpoch();

        // Before going further, let's sync our account and global weights
        (AccountData memory acctData, ) = _checkpointAccount(_account, systemEpoch);
        require(acctData.realizedStake >= _amount, "insufficient weight available");
        _checkpointGlobal(systemEpoch);


        acctData.realizedStake -= uint112(_amount);
        accountData[_account] = acctData;

        uint weightToRemove = _amount * MAX_STAKE_GROWTH_EPOCHS;
        globalWeightInEpoch[systemEpoch] -= weightToRemove;
        accountWeightInEpoch[_account][systemEpoch] -= weightToRemove;
        
        totalSupply -= _amount;

        uint end = block.timestamp + cooldownDuration;
        cooldowns[_account].cooldownEnd = uint104(end);
        cooldowns[_account].underlyingAmount += uint152(_amount);

        // emit Unstaked(_account, systemEpoch, _amount);
        emit Cooldown(_account, _amount, end);

        stakeToken.safeTransfer(address(ESCROW), _amount);
        
        return _amount;
    }

    function unstake(address _receiver) external returns (uint) {
        return _unstake(msg.sender, _receiver);
    }

    function unstakeFor(address _account, address _receiver) external returns (uint) {
        if (msg.sender != _account) {
            ApprovalStatus status = approvedCaller[_account][msg.sender];
            require(
                status == ApprovalStatus.StakeAndUnstake ||
                status == ApprovalStatus.UnstakeOnly,
                "!Permission"
            );
        }
        return _unstake(_account, _receiver);
    }

    function _unstake(address _account, address _receiver) internal returns (uint) {
        UserCooldown storage userCooldown = cooldowns[_account];
        uint256 amount = userCooldown.underlyingAmount;

        require(block.timestamp >= userCooldown.cooldownEnd || cooldownDuration == 0, "InvalidCooldown");

        userCooldown.cooldownEnd = 0;
        userCooldown.underlyingAmount = 0;

        ESCROW.withdraw(_receiver, amount);

        emit Unstaked(_account, amount);
        return amount;
    }
    
    /**
        @notice Get the current realized weight for an account
        @param _account Account to checkpoint.
        @return acctData Most recent account data written to storage.
        @return weight Most current account weight.
        @dev Prefer to use this function over it's view counterpart for
             contract -> contract interactions.
    */
    function checkpointAccount(address _account) external returns (AccountData memory acctData, uint weight) {
        (acctData, weight) = _checkpointAccount(_account, getEpoch());
        accountData[_account] = acctData;
    }

    /**
        @notice Checkpoint an account using a specified epoch limit.
        @dev    To use in the event that significant number of epochs have passed since last 
                heckpoint and single call becomes too expensive.
        @param _account Account to checkpoint.
        @param _epoch Week which we want to checkpoint to.
        @return acctData Most recent account data written to storage.
        @return weight Account weight for provided epoch.
    */
    function checkpointAccountWithLimit(address _account, uint _epoch) external returns (AccountData memory acctData, uint weight) {
        uint systemEpoch = getEpoch();
        if (_epoch >= systemEpoch) _epoch = systemEpoch;
        (acctData, weight) = _checkpointAccount(_account, _epoch);
        accountData[_account] = acctData;
    }

    function _checkpointAccount(address _account, uint _systemEpoch) internal returns (AccountData memory acctData, uint weight){
        acctData = accountData[_account];
        uint lastUpdateEpoch = acctData.lastUpdateEpoch;

        if (_systemEpoch == lastUpdateEpoch) {
            return (acctData, accountWeightInEpoch[_account][lastUpdateEpoch]);
        }

        require(_systemEpoch > lastUpdateEpoch, "specified epoch is older than last update.");

        uint pending = uint(acctData.pendingStake);
        uint realized = acctData.realizedStake;

        if (pending == 0) {
            if (realized != 0) {
                weight = accountWeightInEpoch[_account][lastUpdateEpoch];
                while (lastUpdateEpoch < _systemEpoch) {
                    unchecked{lastUpdateEpoch++;}
                    // Fill in any missing epochs
                    accountWeightInEpoch[_account][lastUpdateEpoch] = weight;
                }
            }
            accountData[_account].lastUpdateEpoch = uint16(_systemEpoch);
            acctData.lastUpdateEpoch = uint16(_systemEpoch);
            return (acctData, weight);
        }

        weight = accountWeightInEpoch[_account][lastUpdateEpoch];
        uint8 bitmap = acctData.updateEpochsBitmap;
        uint targetSyncWeek = min(_systemEpoch, lastUpdateEpoch + MAX_STAKE_GROWTH_EPOCHS);

        // Populate data for missed epochs
        while (lastUpdateEpoch < targetSyncWeek) {
            unchecked{ lastUpdateEpoch++; }
            weight += pending; // Increment weights by epochly growth factor.
            accountWeightInEpoch[_account][lastUpdateEpoch] = weight;

            // Shift left on bitmap as we pass over each epoch.
            bitmap = bitmap << 1;
            if (bitmap & MAX_WEEK_BIT == MAX_WEEK_BIT){ // If left-most bit is true, we have something to realize; push pending to realized.
                // Do any updates needed to realize an amount for an account.
                uint toRealize = accountToRealizeInEpoch[_account][lastUpdateEpoch];
                pending -= toRealize;
                realized += toRealize;
                if (pending == 0) break; // All pending has been realized. No need to continue.
            }
        }

        // Fill in any missed epochs.
        while (lastUpdateEpoch < _systemEpoch){
            unchecked{lastUpdateEpoch++;}
            accountWeightInEpoch[_account][lastUpdateEpoch] = weight;
        }   

        // Write new account data to storage.
        acctData = AccountData({
            updateEpochsBitmap: bitmap,
            pendingStake: uint112(pending),
            realizedStake: uint112(realized),
            lastUpdateEpoch: uint16(_systemEpoch)
        });
    }

    /**
        @notice View function to get the current weight for an account
    */
    function getAccountWeight(address account) external view returns (uint) {
        return getAccountWeightAt(account, getEpoch());
    }

    /**
        @notice Get the weight for an account in a given epoch
    */
    function getAccountWeightAt(address _account, uint _epoch) public view returns (uint) {
        if (_epoch > getEpoch()) return 0;
        
        AccountData memory acctData = accountData[_account];
        
        uint16 lastUpdateEpoch = acctData.lastUpdateEpoch;

        if (lastUpdateEpoch >= _epoch) return accountWeightInEpoch[_account][_epoch]; 

        uint weight = accountWeightInEpoch[_account][lastUpdateEpoch];

        uint pending = uint(acctData.pendingStake);
        if (pending == 0) return weight;

        uint8 bitmap = acctData.updateEpochsBitmap;

        while (lastUpdateEpoch < _epoch) { // Populate data for missed epochs
            unchecked{lastUpdateEpoch++;}
            weight += pending; // Increment weight by 1 epoch

            // Our bitmap is used to determine if epoch has any amount to realize.
            bitmap = bitmap << 1;
            if (bitmap & MAX_WEEK_BIT == MAX_WEEK_BIT){ // If left-most bit is true, we have something to realize; push pending to realized.
                pending -= accountToRealizeInEpoch[_account][lastUpdateEpoch];
                if (pending == 0) break; // All pending has now been realized, let's exit.
            }            
        }
        
        return weight;
    }

    /**
        @notice Get the current total system weight
        @dev Also updates local storage values for total weights. Using
             this function over it's `view` counterpart is preferred for
             contract -> contract interactions.
    */
    function checkpointGlobal() external returns (uint) {
        uint systemEpoch = getEpoch();
        return _checkpointGlobal(systemEpoch);
    }

    /**
        @notice Get the current total system weight
        @dev Also updates local storage values for total weights. Using
             this function over it's `view` counterpart is preferred for
             contract -> contract interactions.
    */
    function _checkpointGlobal(uint systemEpoch) internal returns (uint) {
        // These two share a storage slot.
        uint16 lastUpdateEpoch = globalLastUpdateWeek;
        uint rate = globalGrowthRate;

        uint weight = globalWeightInEpoch[lastUpdateEpoch];

        if (lastUpdateEpoch == systemEpoch){
            return weight;
        }

        while (lastUpdateEpoch < systemEpoch) {
            unchecked{lastUpdateEpoch++;}
            weight += rate;
            globalWeightInEpoch[lastUpdateEpoch] = weight;
            rate -= globalToRealizeInEpoch[lastUpdateEpoch];
        }

        globalGrowthRate = uint112(rate);
        globalLastUpdateWeek = uint16(systemEpoch);

        return weight;
    }

    /**
        @notice Get the system weight for current epoch.
    */
    function getGlobalWeight() external view returns (uint) {
        return getGlobalWeightAt(getEpoch());
    }

    /**
        @notice Get the system weight for a specified epoch in the past.
        @dev querying a epoch in the future will always return 0.
        @param epoch the epoch number to query global weight for.
    */
    function getGlobalWeightAt(uint epoch) public view returns (uint) {
        uint systemEpoch = getEpoch();
        if (epoch > systemEpoch) return 0;

        // Read these together since they are packed in the same slot.
        uint16 lastUpdateEpoch = globalLastUpdateWeek;
        uint rate = globalGrowthRate;

        if (epoch <= lastUpdateEpoch) return globalWeightInEpoch[epoch];

        uint weight = globalWeightInEpoch[lastUpdateEpoch];
        if (rate == 0) {
            return weight;
        }

        while (lastUpdateEpoch < epoch) {
            unchecked {lastUpdateEpoch++;}
            weight += rate;
            rate -= globalToRealizeInEpoch[lastUpdateEpoch];
        }

        return weight;
    }

    /**
        @notice Returns the balance of underlying staked tokens for an account
        @param _account Account to query balance.
        @return balance of account.
    */
    function balanceOf(address _account) external view returns (uint) {
        AccountData memory acctData = accountData[_account];
        return acctData.pendingStake + acctData.realizedStake;
    }

    /**
        @notice Allow another address to stake or unstake on behalf of. Useful for zaps and other functionality.
        @param _caller Address of the caller to approve or unapprove.
        @param _status Enum representing various approval status states.
    */
    function setApprovedCaller(address _caller, ApprovalStatus _status) external {
        approvedCaller[msg.sender][_caller] = _status;
        emit ApprovedCallerSet(msg.sender, _caller, _status);
    }

    function sweep(address _token) external {
        require(msg.sender == owner, "!authorized");
        uint amount = IERC20(_token).balanceOf(address(this));
        if (_token == address(stakeToken)) {
            amount = amount - totalSupply;
        }
        if (amount > 0) IERC20(_token).safeTransfer(owner, amount);
    }


    function getEpoch() public view returns (uint256) {
        return (block.timestamp - START_TIME) / EPOCH_LENGTH;
    }

    function min(uint a, uint b) internal pure returns (uint) {
        return a < b ? a : b;
    }
}