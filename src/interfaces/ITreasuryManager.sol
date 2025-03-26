// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface ITreasuryManager {
    event ManagerSet(address indexed manager);

    function registry() external view returns (address);
    function treasury() external view returns (address);
    function manager() external view returns (address);
    function lpIncentivesReceiver() external view returns (address);
    function retrieveToken(address _token, address _to) external;
    function retrieveTokenExact(address _token, address _to, uint256 _amount) external;
    function retrieveETH(address _to) external;
    function retrieveETHExact(address _to, uint256 _amount) external;
    function setTokenApproval(address _token, address _spender, uint256 _amount) external;
    function execute(address _target, bytes calldata _data) external returns (bool, bytes memory);
    function safeExecute(address _target, bytes calldata _data) external returns (bytes memory);
    function setManager(address _manager) external;
    function setLpIncentivesReceiver(address _receiver) external;
}
