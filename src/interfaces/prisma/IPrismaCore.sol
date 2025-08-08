// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IPrismaCore {
    function feeReceiver() external view returns (address);
    function priceFeed() external view returns (address);
    function owner() external view returns (address);
    function pendingOwner() external view returns (address);
    function ownershipTransferDeadline() external view returns (uint256);
    function guardian() external view returns (address);
    function OWNERSHIP_TRANSFER_DELAY() external view returns (uint256);
    function paused() external view returns (bool);
    function startTime() external view returns (uint256);
    function setFeeReceiver(address _feeReceiver) external;
    function setPriceFeed(address _priceFeed) external;
    function setGuardian(address _guardian) external;
    function setPaused(bool _paused) external;
    function commitTransferOwnership(address newOwner) external;
    function acceptTransferOwnership() external;
    function revokeTransferOwnership() external;
}