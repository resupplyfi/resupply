// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IEmissionsController } from "../../../interfaces/IEmissionsController.sol";
import { IResupplyRegistry } from "../../../interfaces/IResupplyRegistry.sol";
import { IRewards } from "../../../interfaces/IRewards.sol";
import { CoreOwnable } from "../../../dependencies/CoreOwnable.sol";
import { EpochTracker } from "src/dependencies/EpochTracker.sol";
import { SafeERC20 } from "src/libraries/SafeERC20.sol";

contract RetentionReceiver is CoreOwnable, EpochTracker {
    using SafeERC20 for IERC20;

    IEmissionsController public immutable emissionsController;
    IResupplyRegistry public immutable registry;
    IERC20 public immutable govToken;
    string public name;
    address public retentionRewards;

    uint256 public constant MAX_REWARDS = 2_500_000e18;
    uint256 public treasuryAllocationPerEpoch;

    uint256 public distributedRewards;
    uint256 public lastEpoch;

    event TreasuryAllocationPerEpochSet(uint256 _treasuryAllocationPerEpoch);

    constructor(address _core, address _registry, address _emissionsController, address _retentionRewards, uint256 _treasuryAllocationPerEpoch) 
        CoreOwnable(_core)
        EpochTracker(_core) 
    {
        emissionsController = IEmissionsController(_emissionsController);
        govToken = IERC20(address(emissionsController.govToken()));
        // initialized = true; // Mark implementation as initialized
        name = "RetentionReceiver";

        registry = IResupplyRegistry(_registry);
        retentionRewards = _retentionRewards;
        treasuryAllocationPerEpoch = _treasuryAllocationPerEpoch;

        IERC20(govToken).approve(_retentionRewards, type(uint256).max);
    }

    function getReceiverId() external view returns (uint256 id) {
        id = emissionsController.receiverToId(address(this));
        if (id == 0) require(emissionsController.idToReceiver(id).receiver == address(this), "!registered");
    }

    function allocateEmissions() external returns (uint256 amount) {
        amount = emissionsController.fetchEmissions();
    }

    function claimEmissions() external returns (uint256 amount) {
        //once per epoch
        uint256 _lastEpoch = lastEpoch;
        uint256 epochsSince;
        if(_lastEpoch == 0) epochsSince = 1;
        else epochsSince = getEpoch() - _lastEpoch;
        require(epochsSince > 0,"!new epoch");
        lastEpoch = getEpoch();

        //pull from emissions
        emissionsController.fetchEmissions();
        (, uint256 allocated) = emissionsController.allocated(address(this));
        emissionsController.transferFromAllocation(address(this), allocated);

        //pull from treasury
        address treasury = registry.treasury();
        uint256 treasuryAllocation = treasuryAllocationPerEpoch * epochsSince;
        govToken.safeTransferFrom(treasury, address(this), treasuryAllocation);

        //check cap
        amount = govToken.balanceOf(address(this));
        amount = (amount + distributedRewards) > MAX_REWARDS ? MAX_REWARDS - distributedRewards : amount;

        //send
        if(amount > 0){
            IRewards(retentionRewards).queueNewRewards(amount);
            distributedRewards += amount;
        }

        //send back leftovers
        uint256 leftover = govToken.balanceOf(address(this));
        if(leftover > 0){
            govToken.safeTransfer(treasury, leftover);
        }
    }

    // Notice: Get the estimated allocation of emissions for this receiver
    // dev: The return value does not include any pending emissions that have not yet been minted.
    //      To ensure the pending amount is included, first call `allocateEmissions()`
    function claimableEmissions() external view returns (uint256) {
        (, uint256 allocated) = emissionsController.allocated(address(this));
        return allocated;
    }

    function setTreasuryAllocationPerEpoch(uint256 _treasuryAllocationPerEpoch) external onlyOwner {
        treasuryAllocationPerEpoch = _treasuryAllocationPerEpoch;
        emit TreasuryAllocationPerEpochSet(_treasuryAllocationPerEpoch);
    }

    function sweepERC20(address token) external onlyOwner {
        IERC20(token).safeTransfer(registry.treasury(), IERC20(token).balanceOf(address(this)));
    }

}
