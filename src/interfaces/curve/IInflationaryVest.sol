// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

/**
 * @title IInflationaryVest
 * @author Yield Basis
 * @notice Interface for InflationaryVest contract that vests YB token for one address 
 *         which can be changed by governance (admin), proportional to inflation.
 */
interface IInflationaryVest {
    // Events
    event NewRecipient(address indexed recipient, address indexed oldRecipient);
    event Start(uint256 timestamp, uint256 amount);
    event Claim(address indexed recipient, uint256 claimed);

    // State variables (view functions)
    function YB() external view returns (address);
    function INITIAL_YB_RESERVE() external view returns (uint256);
    function recipient() external view returns (address);
    function claimed() external view returns (uint256);
    function initial_vest_reserve() external view returns (uint256);
    function owner() external view returns (address);

    // External functions
    function start() external;
    function set_recipient(address newRecipient) external;
    function claimable() external view returns (uint256);
    function claim() external returns (uint256);
    function transfer_ownership(address newOwner) external;
}