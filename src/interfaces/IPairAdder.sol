pragma solidity 0.8.28;

interface IPairAdder {
    function addPair(address _pair) external;

    function core() external view returns (address);

    function owner() external view returns (address);

    function registry() external view returns (address);
}