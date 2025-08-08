// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface ISwapperOdos {
    function swap(
        address,
        uint256,
        address[] memory _path,
        address
    ) external;

    function updateApprovals() external;

    function revokeApprovals() external;

    function canUpdateApprovals() external view returns (bool);

    function encode(bytes memory payload, address _sellToken, address _buyToken) external pure returns (address[] memory path);

    function decode(address[] memory path) external pure returns (bytes memory payload);

    function recoverERC20(address token, uint256 amount) external;

    // View functions for public state variables
    function odosRouter() external view returns (address);
    function registry() external view returns (address);
    function reusd() external view returns (address);
    function nextPairIndex() external view returns (uint256);
    function approvalsRevoked() external view returns (bool);
}