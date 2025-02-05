// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.22;

import { MultiRewardsDistributor } from './MultiRewardsDistributor.sol';
import { IERC20, SafeERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import { EpochTracker } from '../../dependencies/EpochTracker.sol';
import { DelegatedOps } from '../../dependencies/DelegatedOps.sol';
import { GovStakerEscrow } from './GovStakerEscrow.sol';
import { IResupplyRegistry } from "../../interfaces/IResupplyRegistry.sol";
import { IGovStaker } from "../../interfaces/IGovStaker.sol";

contract GovStaker is MultiRewardsDistributor, EpochTracker, DelegatedOps {
    using SafeERC20 for IERC20;

    uint24 public constant MAX_COOLDOWN_DURATION = 90 days;
    address private immutable _stakeToken;
    GovStakerEscrow public immutable escrow;
    IResupplyRegistry public immutable registry;

    // Account tracking state vars.
    mapping(address account => AccountData data) public accountData;
    mapping(address account => mapping(uint epoch => uint weight)) private accountWeightAt;

    // Global weight tracking state vars.
    uint112 public totalPending;
    uint16 public totalLastUpdateEpoch;
    mapping(uint epoch => uint weight) private totalWeightAt;

    // Cooldown tracking vars.
    uint public cooldownEpochs;
    mapping(address => UserCooldown) public cooldowns;

    // Generic token interface.
    uint private _totalSupply;

    struct AccountData {
        uint112 realizedStake; // Amount of stake that has fully realized weight.
        uint112 pendingStake; // Amount of stake that has not yet fully realized weight.
        uint16 lastUpdateEpoch;
        bool isPermaStaker;
    }

    struct UserCooldown {
        uint104 end;
        uint152 amount;
    }

    error InvalidAmount();
    error InsufficientRealizedStake();
    error InvalidCooldown();
    error InvalidEpoch();
    error InvalidDuration();
    error OldEpoch();

    /* ========== EVENTS ========== */

    event Staked(address indexed account, uint indexed epoch, uint amount);
    event Unstaked(address indexed account, uint amount);
    event Cooldown(address indexed account, uint amount, uint end);
    event CooldownEpochsUpdated(uint24 newDuration);
    event PermaStakerSet(address indexed account);


    /* ========== CONSTRUCTOR ========== */

    /**
        @param _core            The Core protocol contract address.
        @param _token           The token to be staked.
        @param _cooldownEpochs  The number of epochs to cooldown for.
    */
    constructor(
        address _core,
        address _registry,
        address _token,
        uint24 _cooldownEpochs
    ) MultiRewardsDistributor(_core) EpochTracker(_core) {
        escrow = new GovStakerEscrow(address(this), _token);
        _stakeToken = _token;
        cooldownEpochs = _cooldownEpochs;
        registry = IResupplyRegistry(_registry);
    }

    function stake(uint _amount) external returns (uint) {
        return _stake(msg.sender, _amount);
    }

    function stake(address _account, uint _amount) external returns (uint) {
        return _stake(_account, _amount);
    }

    function _stake(address _account, uint _amount) internal updateReward(_account) returns (uint) {
        if (_amount == 0 || _amount >= type(uint112).max) revert InvalidAmount();

        // Before going further, let's sync our account and total weights
        uint systemEpoch = getEpoch();
        (AccountData memory acctData, ) = _checkpointAccount(_account, systemEpoch);
        _checkpointTotal(systemEpoch);

        acctData.pendingStake += uint112(_amount);
        totalPending += uint112(_amount);

        accountData[_account] = acctData;
        _totalSupply += _amount;

        IERC20(_stakeToken).safeTransferFrom(msg.sender, address(this), uint(_amount));
        emit Staked(_account, systemEpoch, _amount);

        return _amount;
    }

    /**
        @notice Request a cooldown tokens from the contract.
        @dev During partial unstake, this will always remove from the least-weighted first.
    */
    function cooldown(address _account, uint _amount) external callerOrDelegated(_account) returns (uint) {
        uint systemEpoch = getEpoch();
        (AccountData memory acctData, ) = _checkpointAccount(_account, systemEpoch);
        require(!acctData.isPermaStaker, "perma staker account");
        return _cooldown(_account, _amount, acctData, systemEpoch); // triggers updateReward
    }

    /**
     * @notice Initiate cooldown and claim any outstanding rewards.
     */
    function exit(address _account) external nonReentrant callerOrDelegated(_account) returns (uint) {
        uint systemEpoch = getEpoch();
        (AccountData memory acctData, ) = _checkpointAccount(_account, systemEpoch);
        require(!acctData.isPermaStaker, "perma staker account");
        _cooldown(_account, acctData.realizedStake, acctData, systemEpoch); // triggers updateReward
        _getRewardFor(_account);
        return acctData.realizedStake;
    }

    function _cooldown(address _account, uint _amount, AccountData memory acctData, uint systemEpoch) internal updateReward(_account) returns (uint) {
        if (_amount == 0 || _amount > type(uint112).max) revert InvalidAmount();
        if (acctData.realizedStake < _amount) revert InsufficientRealizedStake();
        _checkpointTotal(systemEpoch);

        acctData.realizedStake -= uint112(_amount);
        accountData[_account] = acctData;

        totalWeightAt[systemEpoch] -= _amount;
        accountWeightAt[_account][systemEpoch] -= _amount;

        _totalSupply -= _amount;

        UserCooldown memory userCooldown = cooldowns[_account];
        userCooldown.end = uint104(block.timestamp + (cooldownEpochs * epochLength));
        userCooldown.amount += uint152(_amount);
        cooldowns[_account] = userCooldown;

        emit Cooldown(_account, userCooldown.amount, userCooldown.end);
        IERC20(_stakeToken).safeTransfer(address(escrow), _amount);

        return _amount;
    }

    function unstake(address _account, address _receiver) external callerOrDelegated(_account) returns (uint) {
        return _unstake(_account, _receiver);
    }

    function _unstake(address _account, address _receiver) internal returns (uint) {
        UserCooldown storage userCooldown = cooldowns[_account];
        uint256 amount = userCooldown.amount;
        if(amount == 0) return 0;
        if(block.timestamp < userCooldown.end && cooldownEpochs != 0) revert InvalidCooldown();
        delete cooldowns[_account];
        escrow.withdraw(_receiver, amount);
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

        if (_systemEpoch <= lastUpdateEpoch) revert OldEpoch();

        uint pending = uint(acctData.pendingStake);
        uint realized = acctData.realizedStake;

        if (pending == 0) {
            if (realized != 0) {
                weight = accountWeightAt[_account][lastUpdateEpoch];
                while (lastUpdateEpoch < _systemEpoch) {
                    unchecked { lastUpdateEpoch++; }
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
            unchecked { lastUpdateEpoch++; }
            accountWeightAt[_account][lastUpdateEpoch] = weight;
        }

        // Write new account data to storage.
        acctData = AccountData({
            pendingStake: 0,
            realizedStake: uint112(weight),
            lastUpdateEpoch: uint16(_systemEpoch),
            isPermaStaker: acctData.isPermaStaker
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
            unchecked { lastUpdateEpoch++; }
            totalWeightAt[lastUpdateEpoch] = weight;
        }

        return weight;
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setCooldownEpochs(uint24 _epochs) external onlyOwner {
        if (_epochs * epochLength > MAX_COOLDOWN_DURATION) revert InvalidDuration();
        cooldownEpochs = _epochs;
        emit CooldownEpochsUpdated(_epochs);
    }

    function stakeToken() public view override returns (address) {
        return _stakeToken;
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
        if (isCooldownEnabled() && block.timestamp < userCooldown.end) return 0;
        return userCooldown.amount;
    }

    function isCooldownEnabled() public view returns (bool) {
        return cooldownEpochs > 0;
    }

    function isPermaStaker(address _account) public view returns (bool) {
        return accountData[_account].isPermaStaker;
    }

    /* ========== PERMA STAKER FUNCTIONS ========== */

    /**
     * @notice  Set account as a permanent staker, preventing them from ever unstaking their staked tokens. 
     *          This action cannot be undone, and is irreversible.
     */
    function irreversiblyCommitAccountAsPermanentStaker(address _account) external callerOrDelegated(_account) {
        require(!accountData[_account].isPermaStaker, "already perma staker account");
        accountData[_account].isPermaStaker = true;
        emit PermaStakerSet(_account);
    }

    /**
     * @notice Migrates a perma staker's stake to a new staking contract
     * @dev Only callable when cooldown epochs are set to 0
     * @dev The new staking contract must be set in the registry
     * @dev Will claim any pending rewards before migrating
     * @dev The new staking contract must have delegate approval from this contract
     * @return amount The amount of tokens that were migrated to the new staking contract
     */
    function migrateStake() external returns (uint amount) {
        require(cooldownEpochs == 0, "cooldownEpochs != 0");
        IGovStaker staker = IGovStaker(registry.staker());
        require(address(this) != address(staker), "!migrate");
        uint systemEpoch = getEpoch();
        (AccountData memory acctData, ) = _checkpointAccount(msg.sender, systemEpoch);
        require(acctData.isPermaStaker, "not perma staker account");
        _cooldown(msg.sender, acctData.realizedStake, acctData, systemEpoch); // triggers updateReward
        amount = _unstake(msg.sender, address(this));
        _getRewardFor(msg.sender);

        IERC20(_stakeToken).approve(address(staker), amount);
        staker.stake(msg.sender, amount);
        staker.onPermaStakeMigrate(msg.sender);
        return amount;
    }

    function onPermaStakeMigrate(address _account) external virtual {}
}
