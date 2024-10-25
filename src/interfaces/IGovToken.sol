// SPDX-License-Identifier: MIT

pragma solidity ^0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IGovToken is IERC20 {
    // Events
    event FinalizeEmissionsController();
    event EmissionsControllerSet(address indexed emissionsController);

    // State variables
    function controllerFinalized() external view returns (bool);
    function emissionsController() external view returns (address);
    function owner() external view returns (address);
    function core() external view returns (address);
    function initializationEpoch() external view returns (uint256);

    // Functions
    function mint(address _to, uint256 _amount) external;
    function initialize() external returns (bool);
    function setEmissionsController(address _emissionsController) external;
    function finalizeEmissionsController() external;
}
