// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { IAuthHook } from './IAuthHook.sol';

interface ICore {
    event FeeReceiverSet(address feeReceiver);
    event GuardianSet(address guardian);
    event OwnershipTransferred(address oldOwner, address owner);
    event OwnershipTransferStarted(address owner, address pendingOwner, uint256 deadline);
    event ProtocolPaused();

    function execute(address target, bytes calldata data) external;
    
    function acceptOwnership() external;

    function acceptTransferOwnership() external;

    function transferOwnership(address newOwner) external;

    function revokeTransferOwnership() external;

    function setFeeReceiver(address _feeReceiver) external;

    function setGuardian(address _guardian) external;

    function OWNERSHIP_TRANSFER_DELAY() external view returns (uint256);

    function epochLength() external view returns (uint256);

    function startTime() external view returns (uint256);

    function voter() external view returns (address);

    function ownershipTransferDeadline() external view returns (uint256);

    function pendingOwner() external view returns (address);

    function isProtocolPaused() external view returns (bool);

    function pauseProtocol(bool _paused) external;

    function assetPaused(address _asset) external view returns (bool);

    function cancelProposal(uint256 id) external;

    function setOperatorPermissions(
        address caller,
        address target,
        bytes4 selector,
        bool authorized,
        IAuthHook authHook
    ) external;
}
