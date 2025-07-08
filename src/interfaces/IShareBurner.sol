pragma solidity 0.8.28;

interface IShareBurner {
    function burn() external;
    function crvusd() external view returns (address);
    function frxusd() external view returns (address);
    function index() external view returns (uint256);
    function registry() external view returns (address);
}