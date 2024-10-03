// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.22;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IGovStakerEscrow} from "../interfaces/IGovStakerEscrow.sol";

contract GovStaker {
    using SafeERC20 for IERC20;

    IERC20 public immutable stakeToken;
    uint public immutable START_TIME;
    uint public immutable EPOCH_LENGTH;
    IGovStakerEscrow public immutable ESCROW;
    uint24 public constant MAX_COOLDOWN_DURATION = 30 days;
    uint256 public constant PRECISION = 1e18;

    // Account weight tracking state vars.
    mapping(address account => AccountData data) public accountData;
    mapping(address account => mapping(uint epoch => uint weight)) private accountWeightAt;

    // Total weight tracking state vars.
    uint120 public totalPending;
    uint16 public totalLastUpdateEpoch;
    mapping(uint epoch => uint weight) private totalWeightAt;

    // Reward tracking state vars.
    address[] public rewardTokens;
    bool public isRetired;
    mapping(address => Reward) public rewardData;
    mapping(address => mapping(address => uint256)) public rewards;
    mapping(address => mapping(address => uint256))public userRewardPerTokenPaid;

    // Cooldown tracking vars.
    uint public cooldownEpochs; // in epochs
    mapping(address => UserCooldown) public cooldowns;

    // Generic token interface.
    uint public totalSupply;
    uint8 public immutable decimals;

    // Permissioned roles
    address public owner;
    mapping(address account => mapping(address caller => ApprovalStatus approvalStatus)) public approvedCaller;
    mapping(address staker => bool approved) public approvedWeightedStaker;

    struct AccountData {
        uint120 realizedStake;  // Amount of stake that has fully realized weight.
        uint120 pendingStake;   // Amount of stake that has not yet fully realized weight.
        uint16 lastUpdateEpoch;
    }

    struct UserCooldown {
        uint104 end;
        uint152 underlyingAmount;
    }

    struct Reward {
        
        address rewardsDistributor; // address with permission to update reward amount.
        /// @notice The duration of our rewards distribution for staking, default is 7 days.
        uint256 rewardsDuration;
        /// @notice The end (timestamp) of our current or most recent reward period.
        uint256 periodFinish;
        /// @notice The distribution rate of reward token per second.
        uint256 rewardRate;
        /**
         * @notice The last time rewards were updated, triggered by updateReward() or notifyRewardAmount().
         * @dev  Will be the timestamp of the update or the end of the period, whichever is earlier.
         */
        uint256 lastUpdateTime;
        /**
         * @notice The most recent stored amount for rewardPerToken().
         * @dev Updated every time anyone calls the updateReward() modifier.
         */
        uint256 rewardPerTokenStored;
    }

    enum ApprovalStatus {
        None,               // 0. Default value, indicating no approval
        StakeOnly,          // 1. Approved for stake only
        UnstakeOnly,        // 2. Approved for unstake only
        StakeAndUnstake     // 3. Approved for both stake and unstake
    }

    /* ========== MODIFIERS ========== */

    modifier onlyOwner() {
        require(msg.sender == owner, "!Owner");
        _;
    }

    modifier updateReward(address _account) {
        for (uint256 i; i < rewardTokens.length; ++i) {
            address token = rewardTokens[i];
            rewardData[token].rewardPerTokenStored = rewardPerToken(token);
            rewardData[token].lastUpdateTime = lastTimeRewardApplicable(token);
            if (_account != address(0)) {
                rewards[_account][token] = earned(_account, token);
                userRewardPerTokenPaid[_account][token] = rewardData[token]
                    .rewardPerTokenStored;
            }
        }
        _;
    }


    /* ========== EVENTS ========== */

    event Staked(address indexed account, uint indexed epoch, uint amount);
    event Unstaked(address indexed account, uint amount);
    event ApprovedCallerSet(address indexed account, address indexed caller, ApprovalStatus status);
    event Cooldown(address indexed account, uint amount, uint end);
    event CooldownEpochsUpdated(uint24 previousDuration, uint24 newDuration);
    event RewardAdded(address indexed rewardToken, uint256 amount);
    event RewardTokenAdded(address indexed rewardsToken, address indexed rewardsDistributor, uint256 rewardsDuration);
    event Recovered(address indexed token, uint256 amount);
    event RewardsDurationUpdated(address indexed rewardsToken, uint256 duration);


    /* ========== CONSTRUCTOR ========== */

    /**
        @param _token           The token to be staked.
        @param _epochLength    The length of an epoch in seconds.
        @param _owner           Owner is able to control cooldown parameters.
        @param _escrow          Escrow contract to hold cooldown tokens.
        @param _cooldownEpochs  The number of epochs to cooldown for.
    */
    constructor(
        address _token,
        address _owner,
        uint _epochLength,
        IGovStakerEscrow _escrow,
        uint24 _cooldownEpochs
    ) {
        owner = _owner;
        stakeToken = IERC20(_token);
        decimals = IERC20Metadata(_token).decimals();
        EPOCH_LENGTH = _epochLength;
        START_TIME = block.timestamp / _epochLength * _epochLength;
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
            require(
                status == ApprovalStatus.StakeAndUnstake ||
                status == ApprovalStatus.StakeOnly,
                "!Permission"
            );
        }
        
        return _stake(_account, _amount);
    }

    function _stake(address _account, uint _amount) internal returns (uint) {
        require(_amount < type(uint120).max, "invalid amount");

        // Before going further, let's sync our account and total weights
        uint systemEpoch = getEpoch();
        (AccountData memory acctData, ) = _checkpointAccount(_account, systemEpoch);
        _checkpointTotal(systemEpoch);
        
        acctData.pendingStake += uint120(_amount);
        totalPending += uint120(_amount);

        accountData[_account] = acctData;
        totalSupply += _amount;
        
        stakeToken.safeTransferFrom(msg.sender, address(this), uint(_amount));
        emit Staked(_account, systemEpoch, _amount);
        
        return _amount;
    }

    /**
        @notice Request a cooldown tokens from the contract.
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

    function exit(address _account) external returns (uint) {
        if (msg.sender != _account) {
            ApprovalStatus status = approvedCaller[_account][msg.sender];
            require(
                status == ApprovalStatus.StakeAndUnstake ||
                status == ApprovalStatus.UnstakeOnly,
                "!Permission"
            );
        }
        return _cooldown(_account, balanceOf(_account));
    }

    function exitFor(address _account) external returns (uint) {
        if (msg.sender != _account) {
            ApprovalStatus status = approvedCaller[_account][msg.sender];
            require(
                status == ApprovalStatus.StakeAndUnstake ||
                status == ApprovalStatus.UnstakeOnly,
                "!Permission"
            );
        }
        return _cooldown(_account, balanceOf(_account));
    }


    function _cooldown(address _account, uint _amount) internal returns (uint) {
        require(_amount < type(uint120).max, "invalid amount");
        
        uint systemEpoch = getEpoch();

        // Before going further, let's sync our account and total weights
        (AccountData memory acctData, ) = _checkpointAccount(_account, systemEpoch);
        require(acctData.realizedStake >= _amount, "insufficient realized stake");
        _checkpointTotal(systemEpoch);

        acctData.realizedStake -= uint120(_amount);
        accountData[_account] = acctData;

        totalWeightAt[systemEpoch] -= _amount;
        accountWeightAt[_account][systemEpoch] -= _amount;
        
        totalSupply -= _amount;

        uint end = block.timestamp + (cooldownEpochs * EPOCH_LENGTH);
        cooldowns[_account].end = uint104(
            START_TIME + EPOCH_LENGTH * (systemEpoch + 2)// Must complete the active + full next epoch.
        ); 
        cooldowns[_account].underlyingAmount += uint152(_amount);
        emit Cooldown(_account, _amount, end);
        stakeToken.safeTransfer(address(ESCROW), _amount);

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

        require(block.timestamp >= userCooldown.end || cooldownEpochs == 0, "InvalidCooldown");

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
            return (acctData, accountWeightAt[_account][lastUpdateEpoch]);
        }

        require(_systemEpoch > lastUpdateEpoch, "specified epoch is older than last update.");

        uint pending = uint(acctData.pendingStake);
        uint realized = acctData.realizedStake;

        if (pending == 0) {
            if (realized != 0) {
                weight = accountWeightAt[_account][lastUpdateEpoch];
                while (lastUpdateEpoch < _systemEpoch) {
                    unchecked{lastUpdateEpoch++;}
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
        while (lastUpdateEpoch < _systemEpoch){
            unchecked{lastUpdateEpoch++;}
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

        if (lastUpdateEpoch == systemEpoch){
            return weight;
        }

        totalLastUpdateEpoch = uint16(systemEpoch);
        weight += pending;
        totalPending = 0;

        while (lastUpdateEpoch < systemEpoch) {
            unchecked{lastUpdateEpoch++;}
            totalWeightAt[lastUpdateEpoch] = weight;
        }

        return weight;
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

    /**
        @notice Returns the balance of underlying staked tokens for an account
        @param _account Account to query balance.
        @return balance of account.
    */
    function balanceOf(address _account) public view returns (uint) {
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

    /* ========== RESTRICTED FUNCTIONS ========== */

    /**
     * @notice Notify staking contract that it has more reward to account for.
     * @dev May only be called by rewards distribution role. Set up token first via addReward().
     * @param _rewardsToken Address of the rewards token.
     * @param _rewardAmount Amount of reward tokens to add.
     */
    function notifyRewardAmount(
        address _rewardsToken,
        uint256 _rewardAmount
    ) external updateReward(address(0)) {
        Reward memory _rewardData = rewardData[_rewardsToken];
        require(_rewardData.rewardsDistributor == msg.sender, "!authorized");
        require(_rewardAmount > 0, "Reward must be >0");
        require(totalSupply > 0, "Supply must be >0");

        // handle the transfer of reward tokens via `transferFrom` to reduce the number
        // of transactions required and ensure correctness of the reward amount
        IERC20(_rewardsToken).safeTransferFrom(
            msg.sender,
            address(this),
            _rewardAmount
        );

        // store locally to save gas
        uint256 newRewardRate;

        if (block.timestamp >= _rewardData.periodFinish) {
            newRewardRate = _rewardAmount / _rewardData.rewardsDuration;
        } else {
            newRewardRate =
                (_rewardAmount +
                    (_rewardData.periodFinish - block.timestamp) *
                    _rewardData.rewardRate) /
                _rewardData.rewardsDuration;
        }

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        require(
            newRewardRate <=
                (IERC20(_rewardsToken).balanceOf(address(this)) /
                    _rewardData.rewardsDuration),
            "Provided reward too high"
        );

        // store everything locally
        _rewardData.rewardRate = newRewardRate;
        _rewardData.lastUpdateTime = block.timestamp;
        _rewardData.periodFinish =
            block.timestamp +
            _rewardData.rewardsDuration;

        // write to storage
        rewardData[_rewardsToken] = _rewardData;

        emit RewardAdded(_rewardsToken, _rewardAmount);
    }

    /**
     * @notice Add a new reward token to the staking contract.
     * @dev May only be called by owner, and can't be set to zero address. Add reward tokens sparingly, as each new one
     *  will increase gas costs. This must be set before notifyRewardAmount can be used.
     * @param _rewardsToken Address of the rewards token.
     * @param _rewardsDistributor Address of the rewards distributor.
     * @param _rewardsDuration The duration of our rewards distribution for staking in seconds.
     */
    function addReward(
        address _rewardsToken,
        address _rewardsDistributor,
        uint256 _rewardsDuration
    ) external onlyOwner {
        require(
            _rewardsToken != address(0) && _rewardsDistributor != address(0),
            "No zero address"
        );
        require(_rewardsDuration > 0, "Must be >0");
        require(
            rewardData[_rewardsToken].rewardsDuration == 0,
            "Reward already added"
        );

        rewardTokens.push(_rewardsToken);
        rewardData[_rewardsToken].rewardsDistributor = _rewardsDistributor;
        rewardData[_rewardsToken].rewardsDuration = _rewardsDuration;

        emit RewardTokenAdded(_rewardsToken, _rewardsDistributor, _rewardsDuration);
    }

    /**
     * @notice Set rewards distributor address for a given reward token.
     * @dev May only be called by owner, and can't be set to zero address.
     * @param _rewardsToken Address of the rewards token.
     * @param _rewardsDistributor Address of the rewards distributor. This is the only address that can add new rewards
     *  for this token.
     */
    function setRewardsDistributor(
        address _rewardsToken,
        address _rewardsDistributor
    ) external onlyOwner {
        require(
            _rewardsToken != address(0) && _rewardsDistributor != address(0),
            "No zero address"
        );
        rewardData[_rewardsToken].rewardsDistributor = _rewardsDistributor;
    }

    function setCooldownEpochs(uint24 _epochs) external onlyOwner {
        require(_epochs * EPOCH_LENGTH <= MAX_COOLDOWN_DURATION, "Invalid duration");

        uint24 previousDuration = uint24(cooldownEpochs);
        cooldownEpochs = _epochs;
        emit CooldownEpochsUpdated(previousDuration, _epochs);
    }

    /**
     * @notice Set the duration of our rewards period.
     * @dev May only be called by rewards distributor, and must be done after most recent period ends.
     * @param _rewardsToken Address of the rewards token.
     * @param _rewardsDuration New length of period in seconds.
     */
    function setRewardsDuration(
        address _rewardsToken,
        uint256 _rewardsDuration
    ) external {
        Reward memory _rewardData = rewardData[_rewardsToken];
        require(block.timestamp > _rewardData.periodFinish, "Rewards active");
        require(_rewardData.rewardsDistributor == msg.sender, "!authorized");
        require(_rewardsDuration > 0, "Must be >0");

        rewardData[_rewardsToken].rewardsDuration = _rewardsDuration;

        emit RewardsDurationUpdated(_rewardsToken, _rewardsDuration);
    }

    /**
     * @notice Sweep out tokens accidentally sent here.
     * @dev May only be called by owner. If a pool has multiple tokens to sweep out, call this once for each.
     * @param _tokenAddress Address of token to sweep.
     * @param _tokenAmount Amount of tokens to sweep.
     */
    function recoverERC20(
        address _tokenAddress,
        uint256 _tokenAmount
    ) external onlyOwner {
        if (_tokenAddress == address(stakeToken)) revert("!staking token");

        // can only recover reward tokens 90 days after last reward token ends
        bool isRewardToken;
        address[] memory _rewardTokens = rewardTokens;
        uint256 maxPeriodFinish;

        for (uint256 i; i < _rewardTokens.length; ++i) {
            uint256 rewardPeriodFinish = rewardData[_rewardTokens[i]]
                .periodFinish;
            if (rewardPeriodFinish > maxPeriodFinish) {
                maxPeriodFinish = rewardPeriodFinish;
            }

            if (_rewardTokens[i] == _tokenAddress) {
                isRewardToken = true;
            }
        }

        if (isRewardToken) {
            require(
                block.timestamp > maxPeriodFinish + 90 days,
                "wait >90 days"
            );

            // if we do this, automatically sweep all reward token
            _tokenAmount = IERC20(_tokenAddress).balanceOf(address(this));

            // retire this staking contract, this wipes all rewards but still allows all users to withdraw
            isRetired = true;
        }

        IERC20(_tokenAddress).safeTransfer(owner, _tokenAmount);
        emit Recovered(_tokenAddress, _tokenAmount);
    }


    /* ========== VIEWS ========== */

    /**
     * @notice Amount of reward token pending claim by an account.
     * @param _account Account to check earned balance for.
     * @param _rewardsToken Rewards token to check.
     * @return pending Amount of reward token pending claim.
     */
    function earned(
        address _account,
        address _rewardsToken
    ) public view returns (uint256 pending) {
        if (isRetired) {
            return 0;
        }

        pending =
            (balanceOf(_account) *
                (rewardPerToken(_rewardsToken) -
                    userRewardPerTokenPaid[_account][_rewardsToken])) /
            PRECISION +
            rewards[_account][_rewardsToken];
    }

    /**
     * @notice Amount of reward token(s) pending claim by an account.
     * @dev Checks for all rewardTokens.
     * @param _account Account to check earned balance for.
     * @return pending Amount of reward token(s) pending claim.
     */
    function earnedMulti(
        address _account
    ) public view returns (uint256[] memory pending) {
        address[] memory _rewardTokens = rewardTokens;
        uint256 length = _rewardTokens.length;
        pending = new uint256[](length);

        for (uint256 i; i < length; ++i) {
            pending[i] = earned(_account, _rewardTokens[i]);
        }
    }

    /**
     * @notice Reward paid out per whole token.
     * @param _rewardsToken Reward token to check.
     * @return rewardAmount Reward paid out per whole token.
     */
    function rewardPerToken(
        address _rewardsToken
    ) public view returns (uint256 rewardAmount) {
        if (totalSupply == 0) {
            return rewardData[_rewardsToken].rewardPerTokenStored;
        }

        if (isRetired) {
            return 0;
        }

        rewardAmount =
            rewardData[_rewardsToken].rewardPerTokenStored +
            (((lastTimeRewardApplicable(_rewardsToken) -
                rewardData[_rewardsToken].lastUpdateTime) *
                rewardData[_rewardsToken].rewardRate *
                PRECISION) / totalSupply);
    }

    function lastTimeRewardApplicable(
        address _rewardsToken
    ) public view returns (uint256) {
        return
            min(
                block.timestamp,
                rewardData[_rewardsToken].periodFinish
            );
    }

    /// @notice Number reward tokens we currently have.
    function rewardTokensLength() external view returns (uint256) {
        return rewardTokens.length;
    }

    /**
     * @notice Total reward that will be paid out over the reward duration.
     * @dev These values are only updated when notifying, adding, or adjust duration of rewards.
     * @param _rewardsToken Reward token to check.
     * @return Total reward token remaining to be paid out.
     */
    function getRewardForDuration(
        address _rewardsToken
    ) external view returns (uint256) {
        return
            rewardData[_rewardsToken].rewardRate *
            rewardData[_rewardsToken].rewardsDuration;
    }

    /// @notice Get the amount of tokens that have passed cooldown.
    /// @param _account The account to query.
    /// @return . amount of tokens that have passed cooldown.
    function getUnstakableAmount(address _account) external view returns (uint) {
        UserCooldown memory userCooldown = cooldowns[_account];
        if (block.timestamp < userCooldown.end) return 0;
        return userCooldown.underlyingAmount;
    }

    function getEpoch() public view returns (uint256) {
        return (block.timestamp - START_TIME) / EPOCH_LENGTH;
    }

    function isCooldownEnabled() public view returns (bool) {
        return cooldownEpochs > 0;
    }

    function min(uint a, uint b) internal pure returns (uint) {
        return a < b ? a : b;
    }
}