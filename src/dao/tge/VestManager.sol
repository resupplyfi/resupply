// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";


interface IVesting {
    function createVest(address _recipient, uint256 _start, uint256 _duration, uint256 _amount) external returns (uint256);
    function token() external view returns (address);
}

interface IGovToken is IERC20 {
    function INITIAL_SUPPLY() external view returns (uint256);
}

contract VestManager {
    address constant BURN_ADDRESS = address(0);
    
    IVesting immutable public vesting;
    IERC20 immutable public prismaToken;
    uint256 immutable public estRedeemablePrisma;
    uint256 immutable public redemptionRatio;
    bytes32 public immutable MERKLE_ROOT_COMPENSATION;
    bytes32 public immutable MERKLE_ROOT_LOCK_BREAK;
    bytes32 public immutable MERKLE_ROOT_TEAM;
    uint256 public immutable INITIAL_SUPPLY;
    uint256 constant BPS = 10000;

    uint256 constant public VEST_DURATION_TEAM = 1 * 365;
    uint256 constant public VEST_DURATION_REDEMPTION = 5 * 365;
    uint256 constant public VEST_DURATION_LOCK_BREAK = 5 * 365;
    uint256 constant public VEST_DURATION_COMPENSATION = 2 * 365;
    uint256 constant public VEST_DURATION_SUBDAO = 5 * 365;

    mapping(address account => mapping(MerkleClaimType => bool hasClaimed)) public hasClaimed;
    mapping(AllocationType => uint256) public allocations;

    enum MerkleClaimType {
        COMPENSATION,
        LOCK_BREAK,
        TEAM
    }

    enum AllocationType {
        TREASURY,
        SUBDAO1,
        SUBDAO2,
        REDEMPTIONS,
        AIRDROP
    }



    event VestCreated(address indexed account, address indexed recipient, uint256 vestId, uint256 amount);

    constructor(
        address _vesting,
        address _prismaToken,
        uint256 _estRedeemablePrisma, // inclusive of yprisma/cvxprisma
        bytes32[3] memory _merkleRoots, // compensation, lock break, team
        uint256[5] memory _allocationPercentages // treasury, subdao1, subdao2, redemptions (in BPS)
    ) {
        vesting = IVesting(_vesting);
        INITIAL_SUPPLY = IGovToken(vesting.token()).INITIAL_SUPPLY();
        prismaToken = IERC20(_prismaToken);
        estRedeemablePrisma = _estRedeemablePrisma;
        MERKLE_ROOT_COMPENSATION = _merkleRoots[0];
        MERKLE_ROOT_LOCK_BREAK = _merkleRoots[1];
        MERKLE_ROOT_TEAM = _merkleRoots[2];

        uint256 totalPctAllocated;
        for (uint256 i = 0; i < _allocationPercentages.length; i++) {
            totalPctAllocated += _allocationPercentages[i];
            allocations[AllocationType(i)] = _allocationPercentages[i] * INITIAL_SUPPLY / BPS;
        }
        redemptionRatio = allocations[AllocationType.REDEMPTIONS] * 1e18 / estRedeemablePrisma;

        require(totalPctAllocated == BPS, "Total not 100%");
    }

    function merkleClaim(
        address _account,
        address _recipient,
        uint256 _amount,
        MerkleClaimType _type,
        bytes32[] calldata _proof,
        uint256 _index
    ) external {
        // require(false, "!disabled"); // TODO: create claim logic
        require(!hasClaimed[_account][_type], "already claimed");

        bytes32 node = keccak256(abi.encodePacked(_account, _index, _amount));
        require(MerkleProof.verifyCalldata(
            _proof, 
            getMerkleRootByClaimType(_type), 
            node
        ), "invalid proof");

        uint256 vestId = vesting.createVest(
            _recipient,
            block.timestamp,
            getDurationByClaimType(_type),
            _amount
        );
        hasClaimed[_account][_type] = true;
        emit VestCreated(_account, _recipient, vestId, _amount);
    }

    /**
        @notice Redeem PRISMA tokens for RSUP tokens
        @param _to      Address to receive the RSUP tokens
        @param _amount  Amount of PRISMA tokens to redeem
        @dev This function allows users to convert their PRISMA tokens to RSUP tokens
             at a 1:1 ratio. The PRISMA tokens are burned in the process.
    */
    function redeem(address _to, address _recipient, uint256 _amount) external {
        prismaToken.transferFrom(_to, BURN_ADDRESS, _amount);
        vesting.createVest(
            _recipient,
            block.timestamp,
            VEST_DURATION_REDEMPTION,
            _amount * redemptionRatio / 1e18
        );
    }
    

    function getDurationByClaimType(MerkleClaimType _type) internal pure returns (uint256) {
        if (_type == MerkleClaimType.COMPENSATION) {
            return VEST_DURATION_COMPENSATION;
        } else if (_type == MerkleClaimType.LOCK_BREAK) {
            return VEST_DURATION_LOCK_BREAK;
        } else if (_type == MerkleClaimType.TEAM) {
            return VEST_DURATION_TEAM;
        } else {
            revert("Invalid MerkleClaimType");
        }
    }

    function getMerkleRootByClaimType(MerkleClaimType _type) internal view returns (bytes32) {
        if (_type == MerkleClaimType.COMPENSATION) {
            return MERKLE_ROOT_COMPENSATION;
        } else if (_type == MerkleClaimType.LOCK_BREAK) {
            return MERKLE_ROOT_LOCK_BREAK;
        } else if (_type == MerkleClaimType.TEAM) {
            return MERKLE_ROOT_TEAM;
        } else {
            revert("Invalid MerkleClaimType");
        }
    }
}
