// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IAuthHook } from './IAuthHook.sol';

interface ICore {
    struct OperatorAuth {
        bool authorized;
        IAuthHook hook;
    }

    event VoterSet(address indexed newVoter);
    event OperatorExecuted(address indexed caller, address indexed target, bytes data);
    event OperatorSet(address indexed caller, address indexed target, bool authorized, bytes4 selector, IAuthHook authHook);

    function execute(address target, bytes calldata data) external returns (bytes memory);
    function epochLength() external view returns (uint256);
    function startTime() external view returns (uint256);
    function voter() external view returns (address);
    function registry() external view returns (address);
    function ownershipTransferDeadline() external view returns (uint256);
    function pendingOwner() external view returns (address);
    function setOperatorPermissions(
        address caller,
        address target,
        bytes4 selector,
        bool authorized,
        IAuthHook authHook
    ) external;
    function setVoter(address newVoter) external;
    function operatorPermissions(address caller, address target, bytes4 selector) external view returns (bool authorized, IAuthHook hook);
}
