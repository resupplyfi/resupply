pragma solidity 0.8.28;

import { TenderlyHelper } from "script/utils/TenderlyHelper.sol";
import { ICore } from "src/interfaces/ICore.sol";
import { Protocol } from "src/Constants.sol";
import { ITreasury } from "src/interfaces/ITreasury.sol";
import { Upgrades, Options } from "@openzeppelin/foundry-upgrades/Upgrades.sol";

contract BaseAction is TenderlyHelper {
    address public core = Protocol.CORE;
    uint256 public epochLength;
    uint256 public startTime;

    constructor() {
        epochLength = ICore(core).epochLength();
        startTime = ICore(core).startTime();
    }

    function _executeCore(address _target, bytes memory _data) internal returns (bytes memory) {
        return addToBatch(
            core,
            abi.encodeWithSelector(
                ICore.execute.selector, address(_target), _data
            )
        );
    }

    function _executeTreasury(address _target, bytes memory _data) internal returns (bytes memory) {
        bytes memory result = _executeCore(
            Protocol.TREASURY,
            abi.encodeWithSelector(
                ITreasury.safeExecute.selector, 
                _target, 
                _data
            )
        );
        return abi.decode(result, (bytes));
    }

    function setOperatorPermissions(
        bytes4 selector, 
        address caller, 
        address target, 
        bool approve,
        address authHook
    ) internal {
        _executeCore(
            address(Protocol.CORE),
            abi.encodeWithSelector(
                ICore.setOperatorPermissions.selector,
                caller,
                target,
                selector,
                approve,
                authHook
            )
        );
    }

    /**
     * @dev Deploys a UUPS proxy using the given contract as the implementation.
     *
     * @param _contractName Name of the contract to use as the implementation, e.g. "MyContract.sol" or "MyContract.sol:MyContract" or artifact path relative to the project root directory
     * @param _data Encoded call data of the initializer function to call during creation of the proxy, or empty if no initialization is required
     * @return Proxy address
     */
    function deployUUPSProxy(string memory _contractName, bytes memory _data, bool _unsafeSkipAllChecks) internal returns (address) {
        Options memory options;
        options.unsafeSkipAllChecks = _unsafeSkipAllChecks;
        return Upgrades.deployUUPSProxy(
            _contractName,
            _data,
            options
        );
    }

    /**
     * @dev Upgrades a proxy to a new implementation contract. Only supported for UUPS or transparent proxies.
     *
     * Requires that either the `referenceContract` option is set, or the new implementation contract has a `@custom:oz-upgrades-from <reference>` annotation.
     *
     * @param _proxy Address of the proxy to upgrade
     * @param _contractName Name of the new implementation contract to upgrade to, e.g. "MyContract.sol" or "MyContract.sol:MyContract" or artifact path relative to the project root directory
     * @param _data Encoded call data of an arbitrary function to call during the upgrade process, or empty if no function needs to be called during the upgrade
     */
    function upgradeProxy(address _proxy, string memory _contractName, bytes memory _data, bool _unsafeSkipAllChecks) internal {
        Options memory options;
        options.unsafeSkipAllChecks = _unsafeSkipAllChecks;
        Upgrades.upgradeProxy(
            _proxy,
            _contractName,
            _data,
            options
        );
    }

    /**
     * @dev Validates a new implementation contract in comparison with a reference contract, deploys the new implementation contract,
     * and returns its address.
     *
     * Requires that either the `referenceContract` option is set, or the contract has a `@custom:oz-upgrades-from <reference>` annotation.
     *
     * Use this method to prepare an upgrade to be run from an admin address you do not control directly or cannot use from your deployment environment.
     *
     * @param _contractName Name of the contract to deploy, e.g. "MyContract.sol" or "MyContract.sol:MyContract" or artifact path relative to the project root directory
     * @return Address of the new implementation contract
     */
    function deployImplementation(string memory _contractName, bool _unsafeSkipAllChecks) internal returns (address) {
        Options memory options;
        options.unsafeSkipAllChecks = _unsafeSkipAllChecks;
        address implementation = Upgrades.prepareUpgrade(_contractName, options);
        return implementation;
    }

    /**
     * @dev Gets private key using cast wallet with interactive prompt
     * @dev If no params are provided, it will use the DEPLOYER_ACCOUNT and DEPLOYER_PASSWORD from the environment variables
     * @return The private key as bytes32
     */

    function loadPrivateKey() internal returns (bytes32) {
        bool hasPassword = false;
        try vm.envString("DEPLOYER_PASSWORD") returns (string memory) {
            hasPassword = true;
        } catch {
            hasPassword = false;
        }
        return _loadPrivateKey(vm.envString("DEPLOYER_ACCOUNT"), hasPassword ? vm.envString("DEPLOYER_PASSWORD") : "");
    }

    function loadPrivateKey(string memory accountName) internal returns (bytes32) {
        return _loadPrivateKey(accountName, "");
    }

    function loadPrivateKey(string memory accountName, string memory password) internal returns (bytes32) {
        return _loadPrivateKey(accountName, password);
    }

    function _loadPrivateKey(string memory accountName, string memory password) internal returns (bytes32) {
        // Check if password is provided in environment
        bool hasPassword = bytes(password).length > 0;

        // Determine array size based on whether password is present
        uint256 arraySize = hasPassword ? 6 : 4;
        string[] memory inputs = new string[](arraySize);
        
        inputs[0] = "cast";
        inputs[1] = "wallet";
        inputs[2] = "private-key";
        inputs[3] = string.concat("--account=", accountName);
        
        if (hasPassword) {
            inputs[4] = "--password";
            inputs[5] = password;
        }
        
        bytes memory keyBytes = vm.ffi(inputs);
        return bytes32(keyBytes);
    }
}