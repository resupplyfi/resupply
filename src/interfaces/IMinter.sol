pragma solidity ^0.8.22;

interface IMinter {
    function mint(address _to, uint256 _amount) external;
}