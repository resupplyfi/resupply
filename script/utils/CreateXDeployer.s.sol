interface ICreateXDeployer {
    event ContractCreation(address indexed newContract, bytes32 indexed salt);

    function deployCreate(bytes memory initCode) external payable returns (address newContract);
    function deployCreate2(bytes32 salt, bytes memory initCode) external payable returns (address newContract);
    function deployCreate3(bytes32 salt, bytes memory initCode) external payable returns (address newContract);

    function computeCreateAddress(uint256 nonce) external view returns (address);
    function computeCreate2Address(bytes32 salt, bytes32 initCodeHash) external view returns (address);
    function computeCreate3Address(bytes32 salt) external view returns (address);
    function computeCreate3Address(bytes32 salt, address deployer) external view returns (address);   
}

// Deploy a contract to a deterministic address with create2
abstract contract CreateXDeployer {
    ICreateXDeployer public constant createXDeployer = ICreateXDeployer(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);

    function encodeCREATE3Deployment(bytes32 salt, bytes memory initCode) public pure returns (bytes memory) {
        return abi.encodeWithSelector(
            createXDeployer.deployCreate3.selector,
            salt,
            initCode
        );
    }

    function encodeCREATE2Deployment(bytes32 salt, bytes memory initCode) public pure returns (bytes memory) {
        return abi.encodeWithSelector(
            createXDeployer.deployCreate2.selector,
            salt,
            initCode
        );
    }


    function encodeCREATEDeployment(bytes memory initCode) public pure returns (bytes memory) {
        return abi.encodeWithSelector(
            createXDeployer.deployCreate.selector,
            initCode
        );
    }

    /// @notice Creates a salt with embedded settings for deterministic create3 deployment using CreateX
    /// @param deployer The address that will be permissioned to deploy if enablePermissionedDeploy is true
    /// @param enablePermissionedDeploy If true, only the deployer address can deploy using this salt
    /// @param enableCrossChainProtection If true, adds chain-specific protection to prevent same-salt deployments on other chains.
    /// @param randomness Additional entropy that can be added to make the salt unique. May be used to mine an address.
    /// @return bytes32 The computed salt combining all parameters
    function buildGuardedSalt(
        address deployer,
        bool enablePermissionedDeploy, 
        bool enableCrossChainProtection, 
        uint88 randomness
    ) public pure returns (bytes32) {
        return bytes32(
            (enablePermissionedDeploy ? bytes32(uint256(uint160(deployer))) : bytes32(0)) << 96 | // 
            (enableCrossChainProtection ? bytes32(uint256(1)) : bytes32(0)) << 88 | 
            bytes32(uint256(randomness))
        );
    }
}