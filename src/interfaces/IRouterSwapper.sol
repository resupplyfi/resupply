// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IRouterSwapper {
    function name() external view returns (string memory);
    function swap(address account, uint256 amountIn, address[] memory path, address to) external;
    function updateApprovals() external;
    function revokeApprovals() external;
    function canUpdateApprovals() external view returns (bool);
    function encode(bytes memory payload, address sellToken, address buyToken) external pure returns (address[] memory path);
    function decode(address[] memory path) external pure returns (bytes memory payload);
    function recoverERC20(address token, uint256 amount) external;
    function router() external view returns (address);
    function registry() external view returns (address);
    function reusd() external view returns (address);
    function nextPairIndex() external view returns (uint256);
    function approvalsRevoked() external view returns (bool);
}
