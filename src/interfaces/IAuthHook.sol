pragma solidity ^0.8.22;

interface IAuthHook {
    function preHook(address operator, address target, bytes calldata data) external returns (bool);
    function postHook(bytes memory result, address operator, address target, bytes calldata data) external returns (bool);
}
