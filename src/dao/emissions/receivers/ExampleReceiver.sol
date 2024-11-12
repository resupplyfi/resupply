// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IEmissionsController } from "../../../interfaces/IEmissionsController.sol";

contract ExampleReceiver {
    IEmissionsController public immutable emissionsController;
    IERC20 public immutable govToken;
    string public name; // RECOMMENDED

    constructor(address _core, address _emissionsController, string memory _name) {
        emissionsController = IEmissionsController(_emissionsController);
        govToken = IERC20(address(emissionsController.govToken()));
        name = _name;
    }

    // REQUIRED: `getReceiverId()` MUST be present, and must return this receiver's ID from the emissions controller.
    function getReceiverId() external view returns (uint256 id) {
        id = emissionsController.receiverToId(address(this));
        if (id == 0) require(emissionsController.idToReceiver(id).receiver == address(this), "!registered");
    }

    // REQUIRED: `allocateEmissions()` MUST be present and MUST call back to `emissionsController.fetchEmissions()`.
    function allocateEmissions() external returns (uint256 amount) {
        amount = emissionsController.fetchEmissions(); // returns amount newly allocated
        
    }

    // REQUIRED: any function to claim emissions from the receiver's allocated amount
    function claimEmissions(address receiver) external returns (uint256 amount) {
        (, uint256 allocated) = emissionsController.allocated(address(this)); // returns totalamount allocated to receiver
        return emissionsController.transferFromAllocation(receiver, allocated); // pulls from receiver's allocation
    }
}
