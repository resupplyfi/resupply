// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.22;

interface IGovStaker {
    /* ========== EVENTS ========== */
    event RewardAdded(address indexed rewardToken, uint256 amount);
    event RewardTokenAdded(address indexed rewardsToken, address indexed rewardsDistributor, uint256 rewardsDuration);
    event Recovered(address indexed token, uint256 amount);
    event RewardsDurationUpdated(address indexed rewardsToken, uint256 duration);
    event RewardPaid(address indexed user, address indexed rewardToken, uint256 reward);
    event Staked(address indexed account, uint indexed epoch, uint amount);
    event Unstaked(address indexed account, uint amount);
    event Cooldown(address indexed account, uint amount, uint end);
    event CooldownEpochsUpdated(uint24 newDuration);

    /* ========== STRUCTS ========== */
    struct Reward {
        address rewardsDistributor;
        uint256 rewardsDuration;
        uint256 periodFinish;
        uint256 rewardRate;
        uint256 lastUpdateTime;
        uint256 rewardPerTokenStored;
    }

    struct AccountData {
        uint120 realizedStake; // Amount of stake that has fully realized weight.
        uint120 pendingStake; // Amount of stake that has not yet fully realized weight.
        uint16 lastUpdateEpoch;
    }

    struct UserCooldown {
        uint104 end;
        uint152 amount;
    }

    enum ApprovalStatus {
        None, // 0. Default value, indicating no approval
        StakeOnly, // 1. Approved for stake only
        UnstakeOnly, // 2. Approved for unstake only
        StakeAndUnstake // 3. Approved for both stake and unstake
    }

    /* ========== STATE VARIABLES ========== */
    function rewardTokens(uint256 index) external view returns (address);
    function rewardData(address token) external view returns (Reward memory);
    function rewards(address account, address token) external view returns (uint256);
    function userRewardPerTokenPaid(address account, address token) external view returns (uint256);
    function CORE() external view returns (address);
    function PRECISION() external view returns (uint256);
    function ESCROW() external view returns (address);
    function MAX_COOLDOWN_DURATION() external view returns (uint24);
    function totalPending() external view returns (uint120);
    function totalLastUpdateEpoch() external view returns (uint16);
    function cooldownEpochs() external view returns (uint256);
    function decimals() external view returns (uint8);
    function approvedCaller(address account, address caller) external view returns (ApprovalStatus);

    /* ========== EXTERNAL FUNCTIONS ========== */
    function accountData(address account) external view returns (AccountData memory);
    function stakeToken() external view returns (address);
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function getReward() external;
    function getOneReward(address rewardsToken) external;
    function addReward(address rewardsToken, address rewardsDistributor, uint256 rewardsDuration) external;
    function notifyRewardAmount(address rewardsToken, uint256 rewardAmount) external;
    function setRewardsDistributor(address rewardsToken, address rewardsDistributor) external;
    function setRewardsDuration(address rewardsToken, uint256 rewardsDuration) external;
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external;
    function stake(address account, uint amount) external returns (uint);
    function stakeFor(address account, uint amount) external returns (uint);
    function cooldown(address account, uint amount) external returns (uint);
    function cooldowns(address account) external view returns (UserCooldown memory);
    function cooldownFor(address account, uint amount) external returns (uint);
    function exit(address account) external returns (uint);
    function exitFor(address account) external returns (uint);
    function unstake(address account, address receiver) external returns (uint);
    function unstakeFor(address account, address receiver) external returns (uint);
    function checkpointAccount(address account) external returns (AccountData memory, uint weight);
    function checkpointAccountWithLimit(address account, uint epoch) external returns (AccountData memory, uint weight);
    function checkpointTotal() external returns (uint);
    function setApprovedCaller(address caller, ApprovalStatus status) external;
    function setCooldownEpochs(uint24 epochs) external;
    function getAccountWeight(address account) external view returns (uint);
    function getAccountWeightAt(address account, uint epoch) external view returns (uint);
    function getTotalWeight() external view returns (uint);
    function getTotalWeightAt(uint epoch) external view returns (uint);
    function getUnstakableAmount(address account) external view returns (uint);
    function isCooldownEnabled() external view returns (bool);
    function rewardTokensLength() external view returns (uint256);
    function earned(address account, address rewardsToken) external view returns (uint256 pending);
    function earnedMulti(address account) external view returns (uint256[] memory pending);
    function rewardPerToken(address rewardsToken) external view returns (uint256 rewardAmount);
    function lastTimeRewardApplicable(address rewardsToken) external view returns (uint256);
    function getRewardForDuration(address rewardsToken) external view returns (uint256);
    function owner() external view returns (address);
    function guardian() external view returns (address);
    function getEpoch() external view returns (uint);
    function epochLength() external view returns (uint);
    function startTime() external view returns (uint);
    function irreversiblyCommitAccountAsPermanentStaker(address account) external;
    function onPermaStakeMigrate(address account) external;
}
