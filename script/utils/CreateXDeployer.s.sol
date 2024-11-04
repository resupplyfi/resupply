pragma solidity >=0.8.18;

import "forge-std/Script.sol";

interface ICreateXDeployer {
    event ContractCreation(address indexed newContract, bytes32 indexed salt);

    function deployCreate(bytes memory initCode) external payable returns (address newContract);
    function deployCreate2(bytes32 salt, bytes memory initCode) external payable returns (address newContract);
    function deployCreate3(bytes32 salt, bytes memory initCode) external payable returns (address newContract);

    function computeCreateAddress(uint256 nonce) external view returns (address);
    function computeCreate2Address(bytes32 salt, bytes32 initCodeHash) external view returns (address);
    function computeCreate3Address(bytes32 salt) external view returns (address);    
}

// Deploy a contract to a deterministic address with create2
abstract contract CreateXDeployer {
    ICreateXDeployer public constant deployer = ICreateXDeployer(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);
}