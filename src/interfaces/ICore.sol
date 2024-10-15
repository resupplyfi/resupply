// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface ICore {
    event FeeReceiverSet(address feeReceiver);
    event GuardianSet(address guardian);
    event OwnershipTransferred(address oldOwner, address owner);
    event OwnershipTransferStarted(address owner, address pendingOwner, uint256 deadline);
    event Paused();
    event Unpaused();

    function acceptOwnership() external;

    function acceptTransferOwnership() external;

    function transferOwnership(address newOwner) external;

    function revokeTransferOwnership() external;

    function setFeeReceiver(address _feeReceiver) external;

    function setGuardian(address _guardian) external;

    function setPaused(bool _paused) external;

    function OWNERSHIP_TRANSFER_DELAY() external view returns (uint256);

    function epochLength() external view returns (uint256);

    function startTime() external view returns (uint256);

    function feeReceiver() external view returns (address);

    function guardian() external view returns (address);

    function owner() external view returns (address);

    function ownershipTransferDeadline() external view returns (uint256);

    function paused() external view returns (bool);

    function pendingOwner() external view returns (address);
}