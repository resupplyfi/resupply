// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IEmissionsController } from "../../../interfaces/IEmissionsController.sol";
import { EpochTracker } from "../../../dependencies/EpochTracker.sol";

contract BasicReceiver is EpochTracker {
    IEmissionsController public immutable emissionsController;
    IERC20 public immutable govToken;
    string public name;

    uint256 public immutable REWARD_DURATION;

    constructor(address _core, address _emissionsController, string memory _name) EpochTracker(_core) {
        emissionsController = IEmissionsController(_emissionsController);
        govToken = IERC20(address(emissionsController.govToken()));
        name = _name;
        REWARD_DURATION = epochLength;
    }

    function getReceiverId() external view returns (uint256 id) {
        id = emissionsController.receiverToId(address(this));
        if (id == 0) require(emissionsController.idToReceiver(id).receiver == address(this), "!registered");
    }

    function allocateEmissions() external returns (uint256 amount) {
        return _allocateEmissions();
    }

    function _allocateEmissions() internal returns (uint256 amount) {
        amount = emissionsController.fetchEmissions();
        emissionsController.transferFromAllocation(address(this), amount);
    }
}