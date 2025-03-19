// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IVestManager {
    enum AllocationType {
        PERMA_STAKE,
        LICENSING,
        TREASURY,
        REDEMPTIONS,
        AIRDROP_TEAM,
        AIRDROP_VICTIMS,
        AIRDROP_LOCK_PENALTY
    }

    struct Vest {
        uint32 duration;
        uint112 amount;
        uint112 claimed;
    }

    struct ClaimSettings {
        bool allowPermissionlessClaims;
        address recipient;
    }

    // Events
    event TokenRedeemed(address indexed token, address indexed redeemer, address indexed recipient, uint256 amount);
    event MerkleRootSet(AllocationType indexed allocationType, bytes32 root);
    event AirdropClaimed(AllocationType indexed allocationType, address indexed account, address indexed recipient, uint256 amount);
    event InitializationParamsSet();
    event VestCreated(address indexed account, uint256 indexed duration, uint256 amount);
    event Claimed(address indexed account, uint256 amount);
    event ClaimSettingsSet(address indexed account, bool indexed allowPermissionlessClaims, address indexed recipient);

    // View Functions
    function PRECISION() external view returns (uint256);
    function prisma() external view returns (address);
    function yprisma() external view returns (address);
    function cvxprisma() external view returns (address);
    function INITIAL_SUPPLY() external view returns (uint256);
    function BURN_ADDRESS() external view returns (address);
    function initialized() external view returns (bool);
    function redemptionRatio() external view returns (uint256);
    function allocationByType(AllocationType) external view returns (uint256);
    function durationByType(AllocationType) external view returns (uint256);
    function merkleRootByType(AllocationType) external view returns (bytes32);
    function hasClaimed(address, AllocationType) external view returns (bool);
    function VEST_GLOBAL_START_TIME() external view returns (uint256);
    function token() external view returns (IERC20);
    function userVests(address, uint256) external view returns (Vest memory);
    function claimSettings(address) external view returns (ClaimSettings memory);
    function numAccountVests(address _account) external view returns (uint256);
    function getAggregateVestData(address _account) external view returns (
        uint256 _totalAmount,
        uint256 _totalClaimable,
        uint256 _totalClaimed
    );
    function getSingleVestData(address _account, uint256 index) external view returns (
        uint256 _total,
        uint256 _claimable,
        uint256 _claimed,
        uint256 _timeRemaining
    );
    // State-Changing Functions
    function setInitializationParams(
        uint256 _maxRedeemable,
        bytes32[3] memory _merkleRoots,
        address[4] memory _nonUserTargets,
        uint256[8] memory _vestDurations,
        uint256[8] memory _allocPercentages
    ) external;
    function setLockPenaltyMerkleRoot(bytes32 _root, uint256 _allocation) external;
    function merkleClaim(
        address _account,
        address _recipient,
        uint256 _amount,
        AllocationType _type,
        bytes32[] calldata _proof,
        uint256 _index
    ) external;
    function redeem(address _token, address _recipient, uint256 _amount) external;
    function claim(address _account) external returns (uint256 _claimed);
    function setClaimSettings(
        bool _allowPermissionlessClaims,
        address _recipient
    ) external;
}