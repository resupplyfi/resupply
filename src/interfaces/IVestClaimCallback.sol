// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IGovStaker } from "./IGovStaker.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IVestClaimCallback {
    event RecoveredERC20(address indexed token, address indexed recipient, uint256 amount);

    function govStaker() external view returns (IGovStaker);
    function vestManager() external view returns (address);
    function token() external view returns (IERC20);
    
    function onClaim(
        address account,
        address recipient,
        uint256 amount
    ) external returns (bool success);
    
    function recoverERC20(address token, address recipient, uint256 amount) external;
}
