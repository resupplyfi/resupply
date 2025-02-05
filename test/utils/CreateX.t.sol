// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.18;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

interface ICreateXDeployer {
    event ContractCreation(address indexed newContract, bytes32 indexed salt);

    function deployCreate(bytes memory initCode) external payable returns (address newContract);
    function deployCreate2(bytes32 salt, bytes memory initCode) external payable returns (address newContract);
    function deployCreate3(bytes32 salt, bytes memory initCode) external payable returns (address newContract);

    function computeCreateAddress(uint256 nonce) external view returns (address);
    function computeCreate2Address(bytes32 salt, bytes32 initCodeHash) external view returns (address);
    function computeCreate3Address(bytes32 salt) external view returns (address);    
}

contract CreateXTest is Test {

    ICreateXDeployer public constant createXDeployer = ICreateXDeployer(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);
    address deployer = address(0x123);
    bytes32 redeployProtectionFlag = bytes32(uint256(0x01));
    uint88 randomness = type(uint88).max;
    bytes32 salt;

    function setUp() public {
        salt = bytes32(uint256(uint160(deployer)) << 96) | redeployProtectionFlag << 88 | bytes32(uint256(randomness));
    }

    function test_SaltFormat() public {
        console.logBytes32(salt);

        // Extract leftmost 160 bits (20 bytes) and shift right by 96 to get deployer portion
        address extractedDeployer = address(uint160(uint256(salt) >> 96));
        console.log("Deployer portion of salt: %s", extractedDeployer);
        assertEq(extractedDeployer, deployer, "Deployer portion of salt mismatch");

        // Extract protection flag (shift right by 88 and mask to get the byte)
        bytes32 extractedFlag = (salt >> 88) & bytes32(uint256(0xff));
        console.logBytes32(extractedFlag);
        assertEq(extractedFlag, redeployProtectionFlag, "Protection flag mismatch");
        
        // Extract randomness (mask to get last 88 bits)
        uint256 extractedRandomness = uint256(uint88(uint256(salt)));
        console.logBytes32(bytes32(uint256(randomness)));  // Convert to bytes32
        assertEq(extractedRandomness, randomness, "Randomness portion of salt mismatch");
        
    }
}