// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import { CoreOwnable } from "../../dependencies/CoreOwnable.sol";
import { VestManagerBase } from "./VestManagerBase.sol";

interface IGovToken is IERC20 {
    function INITIAL_SUPPLY() external view returns (uint256);
}

contract VestManager is VestManagerBase {
    uint256 constant BPS = 10000;
    address immutable public prisma;
    address immutable public yprisma;
    address immutable public cvxprisma;
    uint256 public immutable INITIAL_SUPPLY;
    address public immutable BURN_ADDRESS;
    
    bool public initParamsSet;
    uint256 public redemptionRatio;
    mapping(AllocationType => uint256) public allocationByType;
    mapping(AllocationType => uint256) public durationByType;
    mapping(AllocationType => bytes32) public merkleRootByType;
    mapping(address account => mapping(AllocationType => bool hasClaimed)) public hasClaimed; // used for airdrops only

    enum AllocationType {
        TREASURY,
        PERMA_LOCKER1,
        PERMA_LOCKER2,
        REDEMPTIONS,
        AIRDROP_TEAM,
        AIRDROP_VICTIMS,
        AIRDROP_LOCK_PENALTY
    }

    event VestCreated(address indexed account, address indexed recipient, uint256 vestId, uint256 amount);
    event TokenRedeemed(address indexed token, address indexed redeemer, address indexed recipient, uint256 amount);
    event InitializationParamsSet();

    constructor(
        address _core,
        address _token,
        address _burnAddress,
        address[3] memory _redemptionTokens, // PRISMA, yPRISMA, cvxPRISMA
        uint256 _timeUntilDeadline
    ) VestManagerBase(_core, _token, _timeUntilDeadline) {
        INITIAL_SUPPLY = IGovToken(_token).INITIAL_SUPPLY();
        require(IERC20(_token).balanceOf(address(this)) == INITIAL_SUPPLY, "invalid initial supply");
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
            with the final value being the total percentage allocated for emissions.
    */
    function setInitializationParams(
        uint256 _maxRedeemable,
        bytes32[3] memory _merkleRoots,
        address[3] memory _nonUserTargets,
        uint256[7] memory _vestDurations,
        uint256[7] memory _allocPercentages
    ) external onlyOwner {
        require(!initParamsSet, "params already set");
        initParamsSet = true;

        uint256 totalPctAllocated;
        uint256 airdropIndex;
        // Set durations and allocations for each allocation type
        for (uint256 i = 0; i <= uint256(type(AllocationType).max); i++) {
            AllocationType allocType = AllocationType(i);
            require(_vestDurations[i] > 0 && _vestDurations[i] <= type(uint32).max, "invalid duration");
            durationByType[allocType] = uint32(_vestDurations[i]);
            totalPctAllocated += _allocPercentages[i];
            uint256 allocation = _allocPercentages[i] * INITIAL_SUPPLY / BPS;
            allocationByType[AllocationType(i)] = allocation;
            // Create vest for non-user targets
            if (i < _nonUserTargets.length) { 
                _createVest(
                    _nonUserTargets[i], 
                    uint32(block.timestamp), 
                    uint112(allocation)
                );
            }
            // Set merkle roots for airdrop allocations
            if (
                allocType == AllocationType.AIRDROP_TEAM || 
                allocType == AllocationType.AIRDROP_LOCK_PENALTY || 
                allocType == AllocationType.AIRDROP_VICTIMS
            ) {
                merkleRootByType[allocType] = _merkleRoots[airdropIndex++];
            }
        }

        // Set the redemption ratio to be used for all PRISMA/yPRISMA/cvxPRISMA redemptions
        redemptionRatio = (
            allocationByType[AllocationType.REDEMPTIONS] * 1e18 / _maxRedeemable
        );
        require(redemptionRatio != 0, "ratio is 0");
        require(totalPctAllocated == BPS, "Total not 100%");
        emit InitializationParamsSet();
    }

    /**
        @notice Set the merkle root for the lock penalty airdrop
        @dev This root must be set later after lock penalty data is finalized
        @param _root Merkle root for the lock penalty airdrop
    */
    function setLockPenaltyMerkleRoot(bytes32 _root) external onlyOwner {
        require(merkleRootByType[AllocationType.AIRDROP_LOCK_PENALTY] == bytes32(0), "root already set");
        merkleRootByType[AllocationType.AIRDROP_LOCK_PENALTY] = _root;
    }

    function merkleClaim(
        address _account,
        address _recipient,
        uint256 _amount,
        AllocationType _type,
        bytes32[] calldata _proof,
        uint256 _index
    ) external {
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

        uint256 vestId = _createVest(
            _recipient,
            uint32(durationByType[_type]),
            uint112(_amount)
        );
        hasClaimed[_account][_type] = true;
        emit VestCreated(_account, _recipient, vestId, _amount);
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

    /**
     * @notice Creates a new vesting schedule funded by an external address
     * @param _funder Address providing the tokens for the vest
     * @param _recipient Address that will receive the vested tokens
     * @param _duration Duration of the vesting period in seconds
     * @param _amount Amount of tokens to vest
     * @dev Only callable by owner. Transfers tokens from funder to this contract.
     */
    function createVest(
        address _funder,
        address _recipient,
        uint256 _duration,
        uint256 _amount
    ) external onlyOwner {
        require(_funder != address(this), "invalid funder");
        require(_amount < type(uint112).max, "invalid amount");
        require(_duration < type(uint32).max, "invalid duration");
        token.transferFrom(_funder, address(this), _amount);
        _createVest(
            _recipient,
            uint32(_duration),
            uint112(_amount)
        );
    }
}
