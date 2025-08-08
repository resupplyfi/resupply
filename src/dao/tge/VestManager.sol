// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import { VestManagerBase } from "./VestManagerBase.sol";

interface IGovToken is IERC20 {
    function INITIAL_SUPPLY() external view returns (uint256);
}

contract VestManager is VestManagerBase {
    uint256 constant PRECISION = 1e18;
    address immutable public prisma;
    address immutable public yprisma;
    address immutable public cvxprisma;
    uint256 public immutable INITIAL_SUPPLY;
    address public immutable BURN_ADDRESS;
    
    bool public initialized;
    uint256 public redemptionRatio;
    mapping(AllocationType => uint256) public allocationByType;
    mapping(AllocationType => uint256) public durationByType;
    mapping(AllocationType => bytes32) public merkleRootByType;
    mapping(address account => mapping(AllocationType => bool hasClaimed)) public hasClaimed; // used for airdrops only

    enum AllocationType {
        PERMA_STAKE,
        LICENSING,
        TREASURY,
        REDEMPTIONS,
        AIRDROP_TEAM,
        AIRDROP_VICTIMS,
        AIRDROP_LOCK_PENALTY
    }

    event TokenRedeemed(address indexed token, address indexed redeemer, address indexed recipient, uint256 amount);
    event MerkleRootSet(AllocationType indexed allocationType, bytes32 root);
    event AirdropClaimed(AllocationType indexed allocationType, address indexed account, address indexed recipient, uint256 amount);
    event InitializationParamsSet();

    constructor(
        address _core,
        address _token,
        address _burnAddress,
        address[3] memory _redemptionTokens // PRISMA, yPRISMA, cvxPRISMA
    ) VestManagerBase(_core, _token) {
        INITIAL_SUPPLY = IGovToken(_token).INITIAL_SUPPLY();
        require(IERC20(_token).balanceOf(address(this)) == INITIAL_SUPPLY, "VestManager not funded");
        BURN_ADDRESS = _burnAddress;
        prisma = _redemptionTokens[0];
        yprisma = _redemptionTokens[1];
        cvxprisma = _redemptionTokens[2];
    }

    /**
        @notice Set the initialization parameters for the vesting contract
        @dev All values must be set in the same order as the AllocationType enum
        @param _maxRedeemable   Maximum amount of PRISMA/yPRISMA/cvxPRISMA that can be redeemed
        @param _merkleRoots     Merkle roots for the airdrop allocations
        @param _nonUserTargets  Addresses to receive the non-user allocations
        @param _vestDurations  Durations of the vesting periods for each type
        @param _allocPercentages Percentages of the initial supply allocated to each type,  
            the first two values being perma-stakers, followed by all other allocation types in order of 
            AllocationType enum.
    */
    function setInitializationParams(
        uint256 _maxRedeemable,
        bytes32[3] memory _merkleRoots,
        address[4] memory _nonUserTargets,
        uint256[8] memory _vestDurations,
        uint256[8] memory _allocPercentages
    ) external onlyOwner {
        require(!initialized, "params already set");
        initialized = true;

        uint256 totalPctAllocated;
        uint256 airdropIndex;
        require(_vestDurations[0] == _vestDurations[1], "perma-staker durations must match");
        for (uint256 i = 0; i < _allocPercentages.length; i++) {
            AllocationType allocType = i == 0 ? AllocationType(i) : AllocationType(i-1); // First two are same type
            require(_vestDurations[i] > 0 && _vestDurations[i] <= type(uint32).max, "invalid duration");
            durationByType[allocType] = uint32(_vestDurations[i]);
            totalPctAllocated += _allocPercentages[i];
            uint256 allocation = _allocPercentages[i] * INITIAL_SUPPLY / PRECISION;
            allocationByType[allocType] += allocation;
            
            if (i < _nonUserTargets.length) { 
                _createVest(
                    _nonUserTargets[i], 
                    uint32(_vestDurations[i]), 
                    uint112(allocation)
                );
                continue;
            }
            if (
                allocType == AllocationType.AIRDROP_TEAM ||
                allocType == AllocationType.AIRDROP_VICTIMS ||
                allocType == AllocationType.AIRDROP_LOCK_PENALTY
            ) {
                // Set merkle roots for airdrop allocations
                merkleRootByType[allocType] = _merkleRoots[airdropIndex];
                emit MerkleRootSet(allocType, _merkleRoots[airdropIndex++]);
            }
        }

        // Set the redemption ratio to be used for all PRISMA/yPRISMA/cvxPRISMA redemptions
        uint256 _redemptionRatio = (
            allocationByType[AllocationType.REDEMPTIONS] * 1e18 / _maxRedeemable
        );
        redemptionRatio = _redemptionRatio;
        require(_redemptionRatio != 0, "ratio is 0");
        require(totalPctAllocated == PRECISION, "Total not 100%");
        emit InitializationParamsSet();
    }

    /**
        @notice Set the merkle root for the lock penalty airdrop
        @dev This root must be set later after lock penalty data is finalized
        @param _root Merkle root for the lock penalty airdrop
        @param _allocation Allocation for the lock penalty airdrop
    */
    function setLockPenaltyMerkleRoot(bytes32 _root, uint256 _allocation) external onlyOwner {
        require(initialized, "init params not set");
        require(merkleRootByType[AllocationType.AIRDROP_LOCK_PENALTY] == bytes32(0), "root already set");
        merkleRootByType[AllocationType.AIRDROP_LOCK_PENALTY] = _root;
        emit MerkleRootSet(AllocationType.AIRDROP_LOCK_PENALTY, _root);
        allocationByType[AllocationType.AIRDROP_LOCK_PENALTY] = _allocation;
    }

    function merkleClaim(
        address _account,
        address _recipient,
        uint256 _amount,
        AllocationType _type,
        bytes32[] calldata _proof,
        uint256 _index
    ) external callerOrDelegated(_account) {
        require(
            _type == AllocationType.AIRDROP_TEAM || 
            _type == AllocationType.AIRDROP_LOCK_PENALTY || 
            _type == AllocationType.AIRDROP_VICTIMS, 
            "invalid type"
        );

        bytes32 _root = merkleRootByType[_type];
        require(_root != bytes32(0), "root not set");

        require(!hasClaimed[_account][_type], "already claimed");
        bytes32 node = keccak256(abi.encodePacked(_account, _index, _amount));
        require(MerkleProof.verifyCalldata(
            _proof, 
            _root, 
            node
        ), "invalid proof");

        _createVest(
            _recipient,
            uint32(durationByType[_type]),
            uint112(_amount)
        );
        hasClaimed[_account][_type] = true;
        emit AirdropClaimed(_type, _account, _recipient, _amount);
    }

    /**
        @notice Redeem PRISMA tokens for RSUP tokens
        @param _token    Token to redeem (PRISMA, yPRISMA or cvxPRISMA)
        @param _recipient Address to receive the RSUP tokens
        @param _amount   Amount of tokens to redeem
        @dev This function allows users to convert their PRISMA tokens to RSUP tokens
             at the redemption ratio. The input tokens are burned in the process.
    */
    function redeem(address _token, address _recipient, uint256 _amount) external {
        require(
            _token == address(prisma) || 
            _token == address(yprisma) || 
            _token == address(cvxprisma), 
            "invalid token"
        );
        require(_amount > 0, "amount too low");
        uint256 _ratio = redemptionRatio;
        require(_ratio != 0, "ratio not set");
        IERC20(_token).transferFrom(msg.sender, BURN_ADDRESS, _amount);
        _createVest(
            _recipient,
            uint32(durationByType[AllocationType.REDEMPTIONS]),
            uint112(_amount * _ratio / 1e18)
        );
        emit TokenRedeemed(_token, msg.sender, _recipient, _amount);
    }
}