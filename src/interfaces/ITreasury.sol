// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface ITreasury {
    event RetrieveToken(address token, uint amount);
    event RetrieveETH(uint amount);

    function retrieveToken(address _token, address _to) external;
    function retrieveTokenExact(address _token, address _to, uint _amount) external;
    function retrieveETH(address _to) external;
    function retrieveETHExact(address _to, uint _amount) external;
    function setTokenApproval(address _token, address _spender, uint256 _amount) external;
    function execute(address target, bytes calldata data) external returns (bool, bytes memory);
    function safeExecute(address target, bytes calldata data) external returns (bytes memory);
    receive() external payable;
}
