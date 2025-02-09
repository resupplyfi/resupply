// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IGovToken is IERC20 {
    // Events
    event MinterSet(address indexed minter);
    event FinalizeMinter();

    // State variables
    function minterFinalized() external view returns (bool);
    function minter() external view returns (address);
    function owner() external view returns (address);
    function core() external view returns (address);
    function initializationEpoch() external view returns (uint256);
    function globalSupply() external view returns (uint256);

    // Functions
    function mint(address _to, uint256 _amount) external;
    function initialize() external returns (bool);
    function setMinter(address _minter) external;
    function finalizeMinter() external;
}
