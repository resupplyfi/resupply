// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.22;

import { MultiRewardsDistributor } from './MultiRewardsDistributor.sol';
import { IERC20, SafeERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import { IERC20Metadata } from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import { IGovStakerEscrow } from '../../interfaces/IGovStakerEscrow.sol';
import { SystemStart } from '../../dependencies/SystemStart.sol';

contract GovStaker is MultiRewardsDistributor, SystemStart {
    using SafeERC20 for IERC20;

    IERC20 private immutable _stakeToken;
    uint public immutable START_TIME;
    uint public immutable EPOCH_LENGTH;
    IGovStakerEscrow public immutable ESCROW;
    uint24 public constant MAX_COOLDOWN_DURATION = 30 days;

    // Account weight tracking state vars.
    mapping(address account => AccountData data) public accountData;
    mapping(address account => mapping(uint epoch => uint weight)) private accountWeightAt;

    // Total weight tracking state vars.
    uint120 public totalPending;
    uint16 public totalLastUpdateEpoch;
    mapping(uint epoch => uint weight) private totalWeightAt;

    // Cooldown tracking vars.
    uint public cooldownEpochs; // in epochs
    mapping(address => UserCooldown) public cooldowns;

    // Generic token interface.
    uint private _totalSupply;
    uint8 public immutable decimals;

    // Permissioned roles
    mapping(address account => mapping(address caller => ApprovalStatus approvalStatus)) public approvedCaller;

    struct AccountData {
        uint120 realizedStake; // Amount of stake that has fully realized weight.
        uint120 pendingStake; // Amount of stake that has not yet fully realized weight.
        uint16 lastUpdateEpoch;
    }

    struct UserCooldown {
        uint104 end;
        uint152 underlyingAmount;
    }

    enum ApprovalStatus {
        None, // 0. Default value, indicating no approval
        StakeOnly, // 1. Approved for stake only
        UnstakeOnly, // 2. Approved for unstake only
        StakeAndUnstake // 3. Approved for both stake and unstake
    }

    /* ========== EVENTS ========== */

    event Staked(address indexed account, uint indexed epoch, uint amount);
    event Unstaked(address indexed account, uint amount);
    event ApprovedCallerSet(address indexed account, address indexed caller, ApprovalStatus status);
    event Cooldown(address indexed account, uint amount, uint end);
    event CooldownEpochsUpdated(uint24 newDuration);


    /* ========== CONSTRUCTOR ========== */

    /**
        @param _core           The core contract address.
        @param _token           The token to be staked.
        @param _escrow          Escrow contract to hold cooldown tokens.
        @param _cooldownEpochs  The number of epochs to cooldown for.
    */
    constructor(
        address _core,
        address _token,
        IGovStakerEscrow _escrow,
        uint24 _cooldownEpochs
    ) MultiRewardsDistributor(_core) SystemStart(_core) {
        EPOCH_LENGTH = CORE.epochLength();
        START_TIME = (block.timestamp / EPOCH_LENGTH) * EPOCH_LENGTH;
        _stakeToken = IERC20(_token);
        decimals = IERC20Metadata(_token).decimals();
        ESCROW = _escrow;
        cooldownEpochs = _cooldownEpochs;
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
            require(status == ApprovalStatus.StakeAndUnstake || status == ApprovalStatus.StakeOnly, '!Permission');
        }

        return _stake(_account, _amount);
    }

    function _stake(address _account, uint _amount) internal updateReward(_account) returns (uint) {
        require(_amount > 0 && _amount < type(uint120).max, "invalid amount");

        // Before going further, let's sync our account and total weights
        uint systemEpoch = getEpoch();
        (AccountData memory acctData, ) = _checkpointAccount(_account, systemEpoch);
        _checkpointTotal(systemEpoch);

        acctData.pendingStake += uint120(_amount);
        totalPending += uint120(_amount);

        accountData[_account] = acctData;
        _totalSupply += _amount;

        _stakeToken.safeTransferFrom(msg.sender, address(this), uint(_amount));
        emit Staked(_account, systemEpoch, _amount);

        return _amount;
    }

    /**
        @notice Request a cooldown tokens from the contract.
        @dev During partial unstake, this will always remove from the least-weighted first.
    */
    function cooldown(uint _amount) external returns (uint) {
        return _cooldown(msg.sender, _amount); // triggers updateReward
    }

    /**
        @notice Unstake tokens from the contract on behalf of another user.
        @dev During partial unstake, this will always remove from the least-weighted first.
    */
    // function unstakeFor(address _account, uint _amount, address _receiver) external returns (uint) {
    function cooldownFor(address _account, uint _amount) external returns (uint) {
        if (msg.sender != _account) {
            ApprovalStatus status = approvedCaller[_account][msg.sender];
            require(status == ApprovalStatus.StakeAndUnstake || status == ApprovalStatus.UnstakeOnly, '!Permission');
        }
        if (_amount == type(uint).max) _amount = balanceOf(_account);
        return _cooldown(_account, _amount); // triggers updateReward
    }

    /**
     * @notice Initiate cooldown and claim any outstanding rewards.
     */
    function exit() external returns (uint) {
        uint balance = balanceOf(msg.sender);
        _cooldown(msg.sender, balance); // triggers updateReward
        _getRewardFor(msg.sender);
        return balance;
    }

    function exitFor(address _account) external returns (uint) {
        if (msg.sender != _account) {
            ApprovalStatus status = approvedCaller[_account][msg.sender];
            require(status == ApprovalStatus.StakeAndUnstake || status == ApprovalStatus.UnstakeOnly, '!Permission');
        }
        uint balance = balanceOf(_account);
        _cooldown(_account, balance); // triggers updateReward
        _getRewardFor(_account);
        return balance;
    }

    function _cooldown(address _account, uint _amount) internal updateReward(_account) returns (uint) {
        require(_amount > 0 && _amount < type(uint120).max, 'invalid amount');

        uint systemEpoch = getEpoch();

        // Before going further, let's sync our account and total weights
        (AccountData memory acctData, ) = _checkpointAccount(_account, systemEpoch);
        require(acctData.realizedStake >= _amount, 'insufficient realized stake');
        _checkpointTotal(systemEpoch);

        acctData.realizedStake -= uint120(_amount);
        accountData[_account] = acctData;

        totalWeightAt[systemEpoch] -= _amount;
        accountWeightAt[_account][systemEpoch] -= _amount;

        _totalSupply -= _amount;

        uint end = block.timestamp + (cooldownEpochs * EPOCH_LENGTH);
        cooldowns[_account].end = uint104(
            START_TIME + EPOCH_LENGTH * (systemEpoch + 2) // Must complete the active + full next epoch.
        );
        cooldowns[_account].underlyingAmount += uint152(_amount);
        emit Cooldown(_account, _amount, end);
        _stakeToken.safeTransfer(address(ESCROW), _amount);

        return _amount;
    }

    function unstake(address _receiver) external returns (uint) {
        return _unstake(msg.sender, _receiver);
    }

    /// @notice Unstake tokens all tokens that have passed cooldown.
    /// @param _account The account from which the tokens are to be unstaked.
    /// @param _receiver The address to which the unstaked tokens will be transferred.
    /// @return The amount of tokens unstaked.
    function unstakeFor(address _account, address _receiver) external returns (uint) {
        if (msg.sender != _account) {
            ApprovalStatus status = approvedCaller[_account][msg.sender];
            require(status == ApprovalStatus.StakeAndUnstake || status == ApprovalStatus.UnstakeOnly, '!Permission');
        }
        return _unstake(_account, _receiver);
    }

    function _unstake(address _account, address _receiver) internal returns (uint) {
        UserCooldown storage userCooldown = cooldowns[_account];
        uint256 amount = userCooldown.underlyingAmount;

        require(block.timestamp >= userCooldown.end || cooldownEpochs == 0, 'InvalidCooldown');

        userCooldown.end = 0;
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
        @param _epoch epoch number which we want to checkpoint up to.
        @return acctData Most recent account data written to storage.
        @return weight Account weight for provided epoch.
    */
    function checkpointAccountWithLimit(
        address _account,
        uint _epoch
    ) external returns (AccountData memory acctData, uint weight) {
        uint systemEpoch = getEpoch();
        if (_epoch >= systemEpoch) _epoch = systemEpoch;
        (acctData, weight) = _checkpointAccount(_account, _epoch);
        accountData[_account] = acctData;
    }

    function _checkpointAccount(
        address _account,
        uint _systemEpoch
    ) internal returns (AccountData memory acctData, uint weight) {
        acctData = accountData[_account];
        uint lastUpdateEpoch = acctData.lastUpdateEpoch;

        if (_systemEpoch == lastUpdateEpoch) {
            return (acctData, accountWeightAt[_account][lastUpdateEpoch]);
        }

        require(_systemEpoch > lastUpdateEpoch, 'specified epoch is older than last update.');

        uint pending = uint(acctData.pendingStake);
        uint realized = acctData.realizedStake;

        if (pending == 0) {
            if (realized != 0) {
                weight = accountWeightAt[_account][lastUpdateEpoch];
                while (lastUpdateEpoch < _systemEpoch) {
                    unchecked {
                        lastUpdateEpoch++;
                    }
                    // Fill in any missing epochs
                    accountWeightAt[_account][lastUpdateEpoch] = weight;
                }
            }
            accountData[_account].lastUpdateEpoch = uint16(_systemEpoch);
            acctData.lastUpdateEpoch = uint16(_systemEpoch);
            return (acctData, weight);
        }

        weight = accountWeightAt[_account][lastUpdateEpoch];

        // Add pending to realized weight
        weight += pending;
        realized = weight;

        // Fill in any missed epochs.
        while (lastUpdateEpoch < _systemEpoch) {
            unchecked {
                lastUpdateEpoch++;
            }
            accountWeightAt[_account][lastUpdateEpoch] = weight;
        }

        // Write new account data to storage.
        acctData = AccountData({
            pendingStake: 0,
            realizedStake: uint120(weight),
            lastUpdateEpoch: uint16(_systemEpoch)
        });
    }

    /**
        @notice Get the current total system weight
        @dev Also updates local storage values for total weights. Using
             this function over it's `view` counterpart is preferred for
             contract -> contract interactions.
    */
    function checkpointTotal() external returns (uint) {
        uint systemEpoch = getEpoch();
        return _checkpointTotal(systemEpoch);
    }

    /**
        @notice Get the current total system weight
        @dev Also updates local storage values for total weights. Using
             this function over it's `view` counterpart is preferred for
             contract -> contract interactions.
    */
    function _checkpointTotal(uint systemEpoch) internal returns (uint) {
        // These two share a storage slot.
        uint16 lastUpdateEpoch = totalLastUpdateEpoch;
        uint pending = totalPending;

        uint weight = totalWeightAt[lastUpdateEpoch];

        if (lastUpdateEpoch == systemEpoch) {
            return weight;
        }

        totalLastUpdateEpoch = uint16(systemEpoch);
        weight += pending;
        totalPending = 0;

        while (lastUpdateEpoch < systemEpoch) {
            unchecked {
                lastUpdateEpoch++;
            }
            totalWeightAt[lastUpdateEpoch] = weight;
        }

        return weight;
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

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setCooldownEpochs(uint24 _epochs) external onlyOwner {
        require(_epochs * EPOCH_LENGTH <= MAX_COOLDOWN_DURATION, 'Invalid duration');
        cooldownEpochs = _epochs;
        emit CooldownEpochsUpdated(_epochs);
    }

    function stakeToken() public view override returns (address) {
        return address(_stakeToken);
    }

    /* ========== OVERRIDES ========== */

    /**
        @notice Returns the balance of underlying staked tokens for an account
        @param _account Account to query balance.
        @return balance of account.
    */
    function balanceOf(address _account) public view override returns (uint) {
        AccountData memory acctData = accountData[_account];
        return acctData.pendingStake + acctData.realizedStake;
    }

    function totalSupply() public view override returns (uint) {
        return _totalSupply;
    }

    /* ========== VIEWS ========== */

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

        if (lastUpdateEpoch >= _epoch) return accountWeightAt[_account][_epoch];

        uint weight = accountWeightAt[_account][lastUpdateEpoch];

        uint pending = uint(acctData.pendingStake);
        if (pending == 0) return weight;

        return pending + weight;
    }

    /**
        @notice Get the system weight for current epoch.
    */
    function getTotalWeight() external view returns (uint) {
        return getTotalWeightAt(getEpoch());
    }

    /**
        @notice Get the system weight for a specified epoch in the past.
        @dev querying a epoch in the future will always return 0.
        @param epoch the epoch number to query total weight for.
    */
    function getTotalWeightAt(uint epoch) public view returns (uint) {
        uint systemEpoch = getEpoch();
        if (epoch > systemEpoch) return 0;

        // Read these together since they are packed in the same slot.
        uint16 lastUpdateEpoch = totalLastUpdateEpoch;
        uint pending = totalPending;

        if (epoch <= lastUpdateEpoch) return totalWeightAt[epoch];

        return totalWeightAt[lastUpdateEpoch] + pending;
    }

    /// @notice Get the amount of tokens that have passed cooldown.
    /// @param _account The account to query.
    /// @return . amount of tokens that have passed cooldown.
    function getUnstakableAmount(address _account) external view returns (uint) {
        UserCooldown memory userCooldown = cooldowns[_account];
        if (block.timestamp < userCooldown.end) return 0;
        return userCooldown.underlyingAmount;
    }

    function isCooldownEnabled() public view returns (bool) {
        return cooldownEpochs > 0;
    }
}
