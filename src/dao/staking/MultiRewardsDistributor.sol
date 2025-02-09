// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IERC20, SafeERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import { ReentrancyGuard } from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import { CoreOwnable } from '../../dependencies/CoreOwnable.sol';
import { IERC20Decimals } from '../../interfaces/IERC20Decimals.sol';

abstract contract MultiRewardsDistributor is ReentrancyGuard, CoreOwnable {
    using SafeERC20 for IERC20;

    address[] public rewardTokens;
    mapping(address => Reward) public rewardData;
    mapping(address => mapping(address => uint256)) public rewards;
    mapping(address => mapping(address => uint256)) public userRewardPerTokenPaid;

    uint256 public constant PRECISION = 1e18;

    function stakeToken() public view virtual returns (address);
    function balanceOf(address account) public view virtual returns (uint256);
    function totalSupply() public view virtual returns (uint256);

    struct Reward {
        address rewardsDistributor; // address with permission to update reward amount.
        uint256 rewardsDuration;
        uint256 periodFinish;
        uint256 rewardRate;
        uint256 lastUpdateTime;
        uint256 rewardPerTokenStored;
    }

    // Add these error declarations at the contract level, after the state variables
    error ZeroAddress();
    error MustBeGreaterThanZero();
    error RewardAlreadyAdded();
    error Unauthorized();
    error SupplyMustBeGreaterThanZero();
    error RewardTooHigh();
    error RewardsStillActive();
    error DecimalsMustBe18();
    error CannotAddStakeToken();
    
    /* ========== EVENTS ========== */

    event RewardAdded(address indexed rewardToken, uint256 amount);
    event RewardTokenAdded(address indexed rewardsToken, address indexed rewardsDistributor, uint256 rewardsDuration);
    event RewardsDurationUpdated(address indexed rewardsToken, uint256 duration);
    event RewardPaid(address indexed user, address indexed rewardToken, uint256 reward);
    event RewardsDistributorSet(address indexed rewardsToken, address indexed rewardsDistributor);

    /* ========== MODIFIERS ========== */

    modifier updateReward(address _account) {
        for (uint256 i; i < rewardTokens.length; ++i) {
            address token = rewardTokens[i];
            rewardData[token].rewardPerTokenStored = rewardPerToken(token);
            rewardData[token].lastUpdateTime = lastTimeRewardApplicable(token);
            if (_account != address(0)) {
                rewards[_account][token] = earned(_account, token);
                userRewardPerTokenPaid[_account][token] = rewardData[token].rewardPerTokenStored;
            }
        }
        _;
    }

    /* ========== CONSTRUCTOR ========== */

    constructor(address _core) CoreOwnable(_core) {}

    /* ========== EXTERNAL STATE CHANGE FUNCTIONS ========== */

    /**
     * @notice Claim any (and all) earned reward tokens.
     * @dev Can claim rewards even if no tokens still staked.
     */
    function getReward() external nonReentrant updateReward(msg.sender) {
        _getRewardFor(msg.sender);
    }

    /**
     * @notice Claim any one earned reward token.
     * @dev Can claim rewards even if no tokens still staked.
     * @param _rewardsToken Address of the rewards token to claim.
     */
    function getOneReward(address _rewardsToken) external nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender][_rewardsToken];
        if (reward > 0) {
            rewards[msg.sender][_rewardsToken] = 0;
            IERC20(_rewardsToken).safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, _rewardsToken, reward);
        }
    }

    /* ========== EXTERNAL RESTRICTED FUNCTIONS ========== */

    /**
     * @notice Add a new reward token to the staking contract.
     * @dev May only be called by owner, and can't be set to zero address. Add reward tokens sparingly, as each new one
     *  will increase gas costs. This must be set before notifyRewardAmount can be used.
     * @param _rewardsToken Address of the rewards token.
     * @param _rewardsDistributor Address of the rewards distributor.
     * @param _rewardsDuration The duration of our rewards distribution for staking in seconds.
     * @dev To avoid precision loss, reward tokens must have 18 decimals.
     */
    function addReward(
        address _rewardsToken,
        address _rewardsDistributor,
        uint256 _rewardsDuration
    ) external onlyOwner {
        if (_rewardsToken == address(0) || _rewardsDistributor == address(0)) revert ZeroAddress();
        if (_rewardsDuration == 0) revert MustBeGreaterThanZero();
        if (rewardData[_rewardsToken].rewardsDuration != 0) revert RewardAlreadyAdded();
        if (IERC20Decimals(_rewardsToken).decimals() != 18) revert DecimalsMustBe18();
        if (_rewardsToken == stakeToken()) revert CannotAddStakeToken();

        rewardTokens.push(_rewardsToken);
        rewardData[_rewardsToken].rewardsDistributor = _rewardsDistributor;
        rewardData[_rewardsToken].rewardsDuration = _rewardsDuration;

        emit RewardTokenAdded(_rewardsToken, _rewardsDistributor, _rewardsDuration);
    }

    /**
     * @notice Notify staking contract that it has more reward to account for.
     * @dev May only be called by rewards distribution role. Set up token first via addReward().
     * @param _rewardsToken Address of the rewards token.
     * @param _rewardAmount Amount of reward tokens to add.
     */
    function notifyRewardAmount(address _rewardsToken, uint256 _rewardAmount) external updateReward(address(0)) {
        Reward memory _rewardData = rewardData[_rewardsToken];
        if (_rewardData.rewardsDistributor != msg.sender) revert Unauthorized();
        if (_rewardAmount == 0) revert MustBeGreaterThanZero();
        if (totalSupply() == 0) revert SupplyMustBeGreaterThanZero();

        // handle the transfer of reward tokens via `transferFrom` to reduce the number
        // of transactions required and ensure correctness of the reward amount
        IERC20(_rewardsToken).safeTransferFrom(msg.sender, address(this), _rewardAmount);

        // store locally to save gas
        uint256 newRewardRate;

        if (block.timestamp >= _rewardData.periodFinish) {
            newRewardRate = _rewardAmount / _rewardData.rewardsDuration;
        } else {
            newRewardRate =
                (_rewardAmount + (_rewardData.periodFinish - block.timestamp) * _rewardData.rewardRate) /
                _rewardData.rewardsDuration;
        }

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        if (newRewardRate > (IERC20(_rewardsToken).balanceOf(address(this)) / _rewardData.rewardsDuration)) {
            revert RewardTooHigh();
        }

        _rewardData.rewardRate = newRewardRate;
        _rewardData.lastUpdateTime = block.timestamp;
        _rewardData.periodFinish = block.timestamp + _rewardData.rewardsDuration;
        rewardData[_rewardsToken] = _rewardData; // Write to storage

        emit RewardAdded(_rewardsToken, _rewardAmount);
    }

    /**
     * @notice Set rewards distributor address for a given reward token.
     * @dev May only be called by owner, and can't be set to zero address.
     * @param _rewardsToken Address of the rewards token.
     * @param _rewardsDistributor Address of the rewards distributor. This is the only address that can add new rewards
     *  for this token.
     */
    function setRewardsDistributor(address _rewardsToken, address _rewardsDistributor) external onlyOwner {
        if (_rewardsToken == address(0) || _rewardsDistributor == address(0)) revert ZeroAddress();
        rewardData[_rewardsToken].rewardsDistributor = _rewardsDistributor;
        emit RewardsDistributorSet(_rewardsToken, _rewardsDistributor);
    }

    /**
     * @notice Set the duration of our rewards period.
     * @dev May only be called by rewards distributor, and must be done after most recent period ends.
     * @param _rewardsToken Address of the rewards token.
     * @param _rewardsDuration New length of period in seconds.
     */
    function setRewardsDuration(address _rewardsToken, uint256 _rewardsDuration) external {
        Reward memory _rewardData = rewardData[_rewardsToken];
        if (block.timestamp <= _rewardData.periodFinish) revert RewardsStillActive();
        if (_rewardData.rewardsDistributor != msg.sender) revert Unauthorized();
        if (_rewardsDuration == 0) revert MustBeGreaterThanZero();

        rewardData[_rewardsToken].rewardsDuration = _rewardsDuration;

        emit RewardsDurationUpdated(_rewardsToken, _rewardsDuration);
    }

    /**
     * @notice Sweep out tokens accidentally sent here.
     * @dev May only be called by owner. If a pool has multiple tokens to sweep out, call this once for each.
     * @param _tokenAddress Address of token to sweep.
     * @param _tokenAmount Amount of tokens to sweep.
     */
    function recoverERC20(address _tokenAddress, uint256 _tokenAmount) external onlyOwner {
        if (_tokenAddress == stakeToken()) {
            _tokenAmount = IERC20(_tokenAddress).balanceOf(address(this)) - totalSupply();
            if (_tokenAmount > 0) {
                IERC20(_tokenAddress).safeTransfer(owner(), _tokenAmount);
            }
            return;
        }

        address[] memory _rewardTokens = rewardTokens;

        for (uint256 i; i < _rewardTokens.length; ++i) {
            if (_rewardTokens[i] == _tokenAddress) {
                return; // Can't recover reward token
            }
        }

        IERC20(_tokenAddress).safeTransfer(owner(), _tokenAmount);
    }


    /* ========== INTERNAL FUNCTIONS ========== */

    // internal function to get rewards.
    function _getRewardFor(address _recipient) internal {
        for (uint256 i; i < rewardTokens.length; ++i) {
            address _rewardsToken = rewardTokens[i];
            uint256 reward = rewards[_recipient][_rewardsToken];
            if (reward > 0) {
                rewards[_recipient][_rewardsToken] = 0;
                IERC20(_rewardsToken).safeTransfer(_recipient, reward);
                emit RewardPaid(_recipient, _rewardsToken, reward);
            }
        }
    }

    function min(uint a, uint b) internal pure returns (uint) {
        return a < b ? a : b;
    }

    /* ========== VIEWS ========== */

    /**
     * @notice Amount of reward token pending claim by an account.
     * @param _account Account to check earned balance for.
     * @param _rewardsToken Rewards token to check.
     * @return pending Amount of reward token pending claim.
     */
    function earned(address _account, address _rewardsToken) public view returns (uint256 pending) {
        pending = (
                balanceOf(_account) 
                * (
                    rewardPerToken(_rewardsToken) 
                    - userRewardPerTokenPaid[_account][_rewardsToken]
                )
            ) 
            / PRECISION 
            + rewards[_account][_rewardsToken];
    }

    /**
     * @notice Amount of reward token(s) pending claim by an account.
     * @dev Checks for all rewardTokens.
     * @param _account Account to check earned balance for.
     * @return pending Amount of reward token(s) pending claim.
     */
    function earnedMulti(address _account) public view returns (uint256[] memory pending) {
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
    function rewardPerToken(address _rewardsToken) public view returns (uint256 rewardAmount) {
        if (totalSupply() == 0) {
            return rewardData[_rewardsToken].rewardPerTokenStored;
        }

        rewardAmount =
            rewardData[_rewardsToken].rewardPerTokenStored +
            (((lastTimeRewardApplicable(_rewardsToken) - rewardData[_rewardsToken].lastUpdateTime) *
                rewardData[_rewardsToken].rewardRate *
                PRECISION) / totalSupply());
    }

    function lastTimeRewardApplicable(address _rewardsToken) public view returns (uint256) {
        return min(block.timestamp, rewardData[_rewardsToken].periodFinish);
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
    function getRewardForDuration(address _rewardsToken) external view returns (uint256) {
        return rewardData[_rewardsToken].rewardRate * rewardData[_rewardsToken].rewardsDuration;
    }
}