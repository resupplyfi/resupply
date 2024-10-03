// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.22;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract MultiRewardsDistributor {
    using SafeERC20 for IERC20;

    // Reward tracking state vars.
    address[] public rewardTokens;
    bool public isRetired;
    mapping(address => Reward) public rewardData;
    mapping(address => mapping(address => uint256)) public rewards;
    mapping(address => mapping(address => uint256))
        public userRewardPerTokenPaid;

    uint256 public constant PRECISION = 1e18;

    function stakeToken() public view virtual returns (address);
    function owner() public view virtual returns (address);
    function balanceOf(address account) public view virtual returns (uint256);
    function totalSupply() public view virtual returns (uint256);

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

    /* ========== EVENTS ========== */
    event RewardAdded(address indexed rewardToken, uint256 amount);
    event RewardTokenAdded(
        address indexed rewardsToken,
        address indexed rewardsDistributor,
        uint256 rewardsDuration
    );
    event Recovered(address indexed token, uint256 amount);
    event RewardsDurationUpdated(
        address indexed rewardsToken,
        uint256 duration
    );

    /* ========== MODIFIERS ========== */
    modifier onlyOwner() {
        require(msg.sender == owner(), "!Owner");
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

    /* ========== RESTRICTED FUNCTIONS ========== */

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

        emit RewardTokenAdded(
            _rewardsToken,
            _rewardsDistributor,
            _rewardsDuration
        );
    }

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
        require(totalSupply() > 0, "Supply must be >0");

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
        if (_tokenAddress == address(stakeToken())) revert("!staking token");

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

        IERC20(_tokenAddress).safeTransfer(owner(), _tokenAmount);
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
        if (totalSupply() == 0) {
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
                PRECISION) / totalSupply());
    }

    function lastTimeRewardApplicable(
        address _rewardsToken
    ) public view returns (uint256) {
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
    function getRewardForDuration(
        address _rewardsToken
    ) external view returns (uint256) {
        return
            rewardData[_rewardsToken].rewardRate *
            rewardData[_rewardsToken].rewardsDuration;
    }

    function min(uint a, uint b) internal pure returns (uint) {
        return a < b ? a : b;
    }
}
