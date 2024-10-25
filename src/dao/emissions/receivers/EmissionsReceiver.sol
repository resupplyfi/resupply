// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IEmissionsController } from "../../../interfaces/IEmissionsController.sol";

contract EmissionsReceiver {
    IEmissionsController public immutable emissionsController;
    IERC20 public immutable govToken;
    string public name;
    uint256 public lastFetchEpoch;

    constructor(address _emissionsController, string memory _name) {
        emissionsController = IEmissionsController(_emissionsController);
        govToken = IERC20(address(emissionsController.govToken()));
        name = _name;
    }


    function fetchAllocatedEmissions() external {
        _fetchAllocatedEmissions();
    }

    function _fetchAllocatedEmissions() internal {
        // dev: should run this on all rewards actions
        uint256 amount = emissionsController.fetchEmissions();
        // dev: do something with amount
    }

    function claimReward(address _recipient) external {
        // TODO: Logic to determine amount
        uint256 amount;
        emissionsController.fetchEmissions();
        emissionsController.transferFromAllocation(_recipient, amount);
    }

}

