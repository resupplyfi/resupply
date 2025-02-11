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
    ICreateXDeployer public constant createXFactory = ICreateXDeployer(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);

    function encodeCREATE3Deployment(bytes32 salt, bytes memory initCode) public pure returns (bytes memory) {
        return abi.encodeWithSelector(
            ICreateXDeployer.deployCreate3.selector,
            salt,
            initCode
        );
    }

    function encodeCREATE2Deployment(bytes32 salt, bytes memory initCode) public pure returns (bytes memory) {
        return abi.encodeWithSelector(
            ICreateXDeployer.deployCreate2.selector,
            salt,
            initCode
        );
    }


    function encodeCREATEDeployment(bytes memory initCode) public pure returns (bytes memory) {
        return abi.encodeWithSelector(
            ICreateXDeployer.deployCreate.selector,
            initCode
        );
    }

    function computeCreate3AddressFromSaltPreimage(bytes32 saltPreimage, address deployer, bool enablePermissionedDeploy, bool enableCrossChainProtection) public view returns (address) {
        if (enablePermissionedDeploy && !enableCrossChainProtection) {
            return createXFactory.computeCreate3Address(
                _efficientHash({a: bytes32(uint256(uint160(deployer))), b: saltPreimage})
            );
        } else if (enablePermissionedDeploy && enableCrossChainProtection) {
            return createXFactory.computeCreate3Address(
                keccak256(abi.encode(msg.sender, block.chainid, saltPreimage))
            );
        } else if (!enablePermissionedDeploy && enableCrossChainProtection) {
            return createXFactory.computeCreate3Address(
                _efficientHash({a: bytes32(block.chainid), b: saltPreimage})
            );
        } else {
            return createXFactory.computeCreate3Address(keccak256(abi.encode(saltPreimage)));
        }
    }

    function computeCreate2AddressFromSaltPreimage(bytes32 saltPreimage, bytes memory initCode) public view returns (address) {
        return createXFactory.computeCreate2Address(keccak256(abi.encode(saltPreimage)), keccak256(initCode));
    }

    function isAlreadyDeployedCreate2(bytes32 saltPreimage, bytes memory initCode) public view returns (bool) {
        return addressHasCode(computeCreate2AddressFromSaltPreimage(saltPreimage, initCode));
    }

    function isAlreadyDeployedCreate3(bytes32 saltPreimage, address deployer, bool enablePermissionedDeploy, bool enableCrossChainProtection) public view returns (bool) {
        return addressHasCode(computeCreate3AddressFromSaltPreimage(saltPreimage, deployer, enablePermissionedDeploy, enableCrossChainProtection));
    }

    function addressHasCode(address addr) public view returns (bool) {
        return addr.code.length > 0;
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
            (enablePermissionedDeploy ? bytes32(uint256(uint160(deployer))) : bytes32(0)) << 96 | // left 160 bits specify permissioned deployer
            (enableCrossChainProtection ? bytes32(uint256(1)) : bytes32(0)) << 88 | // byte specifing 0x01 for cross-chain protection; 0x00 for none
            bytes32(uint256(randomness)) // final 128 bits are randomness
        );
    }

    function buildRandomSalt() public view returns (bytes32) {
        return keccak256(
                abi.encode(
                    blockhash(block.number - 32),
                    block.coinbase,
                    block.number,
                    block.timestamp,
                    block.prevrandao,
                    block.chainid,
                    msg.sender
                )
            );
    }

    function buildRandom88Bits() public view returns (uint88) {
        return uint88(uint256(keccak256(abi.encode(
            blockhash(block.number - 32),
            block.coinbase,
            block.number,
            block.timestamp,
            block.prevrandao,
            block.chainid,
            msg.sender
        ))));
    }

    function _efficientHash(bytes32 a, bytes32 b) internal pure returns (bytes32 hash) {
        assembly ("memory-safe") {
            mstore(0x00, a)
            mstore(0x20, b)
            hash := keccak256(0x00, 0x40)
        }
    }
    ICreateXDeployer public constant createXDeployer = ICreateXDeployer(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);

    function encodeCREATE3Deployment(bytes32 salt, bytes memory initCode) public pure returns (bytes memory) {
        return abi.encodeWithSelector(
            ICreateXDeployer.deployCreate3.selector,
            salt,
            initCode
        );
    }

    function encodeCREATE2Deployment(bytes32 salt, bytes memory initCode) public pure returns (bytes memory) {
        return abi.encodeWithSelector(
            ICreateXDeployer.deployCreate2.selector,
            salt,
            initCode
        );
    }


    function encodeCREATEDeployment(bytes memory initCode) public pure returns (bytes memory) {
        return abi.encodeWithSelector(
            ICreateXDeployer.deployCreate.selector,
            initCode
        );
    }

    function computeCreate3AddressFromSaltPreimage(bytes32 saltPreimage, address deployer, bool enablePermissionedDeploy, bool enableCrossChainProtection) public view returns (address) {
        if (enablePermissionedDeploy && !enableCrossChainProtection) {
            return createXFactory.computeCreate3Address(
                _efficientHash({a: bytes32(uint256(uint160(deployer))), b: saltPreimage})
            );
        } else if (enablePermissionedDeploy && enableCrossChainProtection) {
            return createXFactory.computeCreate3Address(
                keccak256(abi.encode(msg.sender, block.chainid, saltPreimage))
            );
        } else if (!enablePermissionedDeploy && enableCrossChainProtection) {
            return createXFactory.computeCreate3Address(
                _efficientHash({a: bytes32(block.chainid), b: saltPreimage})
            );
        } else {
            return createXFactory.computeCreate3Address(keccak256(abi.encode(saltPreimage)));
        }
    }

    function computeCreate2AddressFromSaltPreimage(bytes32 saltPreimage, bytes memory initCode) public view returns (address) {
        return createXFactory.computeCreate2Address(keccak256(abi.encode(saltPreimage)), keccak256(initCode));
    }

    function isAlreadyDeployedCreate2(bytes32 saltPreimage, bytes memory initCode) public view returns (bool) {
        return addressHasCode(computeCreate2AddressFromSaltPreimage(saltPreimage, initCode));
    }

    function isAlreadyDeployedCreate3(bytes32 saltPreimage, address deployer, bool enablePermissionedDeploy, bool enableCrossChainProtection) public view returns (bool) {
        return addressHasCode(computeCreate3AddressFromSaltPreimage(saltPreimage, deployer, enablePermissionedDeploy, enableCrossChainProtection));
    }

    function addressHasCode(address addr) public view returns (bool) {
        return addr.code.length > 0;
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
            (enablePermissionedDeploy ? bytes32(uint256(uint160(deployer))) : bytes32(0)) << 96 | // left 160 bits specify permissioned deployer
            (enableCrossChainProtection ? bytes32(uint256(1)) : bytes32(0)) << 88 | // byte specifing 0x01 for cross-chain protection; 0x00 for none
            bytes32(uint256(randomness)) // final 128 bits are randomness
        );
    }

    function buildRandomSalt() public view returns (bytes32) {
        return keccak256(
                abi.encode(
                    blockhash(block.number - 32),
                    block.coinbase,
                    block.number,
                    block.timestamp,
                    block.prevrandao,
                    block.chainid,
                    msg.sender
                )
            );
    }

    function buildRandom88Bits() public view returns (uint88) {
        return uint88(uint256(keccak256(abi.encode(
            blockhash(block.number - 32),
            block.coinbase,
            block.number,
            block.timestamp,
            block.prevrandao,
            block.chainid,
            msg.sender
        ))));
    }

    function _efficientHash(bytes32 a, bytes32 b) internal pure returns (bytes32 hash) {
        assembly ("memory-safe") {
            mstore(0x00, a)
            mstore(0x20, b)
            hash := keccak256(0x00, 0x40)
        }
    }
}