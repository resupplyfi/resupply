// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title ResupplyPairDeployer
 * @notice Based on code from Drake Evans and Frax Finance's pair deployer contract (https://github.com/FraxFinance/fraxlend), adapted for Resupply Finance
 */

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { CoreOwnable } from '../dependencies/CoreOwnable.sol';
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { SSTORE2 } from "@rari-capital/solmate/src/utils/SSTORE2.sol";
import { BytesLib } from "solidity-bytes-utils/contracts/BytesLib.sol";
import { IResupplyRegistry } from "../interfaces/IResupplyRegistry.sol";
import { SafeERC20 } from "../libraries/SafeERC20.sol";


contract ResupplyPairDeployer is CoreOwnable {
    using Strings for uint256;
    using SafeERC20 for IERC20;

    // Storage
    address public contractAddress1;
    address public contractAddress2;
    mapping(address => uint256) public collateralId;

    // immutable contracts
    address public immutable registry;
    address public immutable govToken;
    mapping(address => bool) public operators;

    /// @notice Emits when a new pair is deployed
    /// @notice The ```LogDeploy``` event is emitted when a new Pair is deployed
    /// @param address_ The address of the pair
    /// @param collateral The address of the Collateral Token contract
    /// @param name The name of the Pair
    /// @param configData The config data of the Pair
    /// @param immutables The immutables of the Pair
    /// @param customConfigData The custom config data of the Pair
    event LogDeploy(
        address indexed address_,
        address indexed collateral,
        string name,
        bytes configData,
        bytes immutables,
        bytes customConfigData
    );

    event SetOperator(address indexed _op, bool _valid);

    constructor(address _core,address _registry, address _govToken, address _initialoperator) CoreOwnable(_core){
        registry = _registry;
        govToken = _govToken;
        operators[_initialoperator] = true;
        operators[_core] = true;
        emit SetOperator(_initialoperator, true);
    }

    function version() external pure returns (uint256 _major, uint256 _minor, uint256 _patch) {
        return (1, 0, 0);
    }

    // ============================================================================================
    // Functions: View Functions
    // ============================================================================================

    function getNextName(
        address _collateral
    ) public view returns (string memory _name) {
        uint256 _collateralId = collateralId[_collateral] + 1;
        string memory _baseName = string(
            abi.encodePacked(
                "Resupply Pair ",
                " (",
                IERC20(_collateral).safeName(),
                ")"
            )
        );
        _name = string(abi.encodePacked(_baseName, " - ", _collateralId.toString()));
        if(IResupplyRegistry(registry).pairsByName(_name) != address(0)){
            revert NonUniqueName();
        }
    }

    // ============================================================================================
    // Functions: Setters
    // ============================================================================================

    function setOperator(address _operator, bool _valid) external onlyOwner{
        operators[_operator] = _valid;
        emit SetOperator(_operator, _valid);
    }

    /// @notice The ```setCreationCode``` function sets the bytecode for the ResupplyPair
    /// @dev splits the data if necessary to accommodate creation code that is slightly larger than 24kb
    /// @param _creationCode The creationCode for the Resupply Pair
    function setCreationCode(bytes calldata _creationCode) external onlyOwner{
        // If the creation code is larger than 13kb, split it into two parts
        if (_creationCode.length > 13_000) {
            bytes memory _firstHalf = BytesLib.slice(_creationCode, 0, 13_000);
            bytes memory _secondHalf = BytesLib.slice(_creationCode, 13_000, _creationCode.length - 13_000);
            contractAddress1 = SSTORE2.write(_firstHalf);
            contractAddress2 = SSTORE2.write(_secondHalf);
        }else{
            contractAddress1 = SSTORE2.write(_creationCode);
            contractAddress2 = address(0);
        }
    }

    // ============================================================================================
    // Functions: Internal Methods
    // ============================================================================================

    /// @notice The ```_deploy``` function is an internal function with deploys the pair
    /// @param _configData abi.encode(address _asset, address _collateral, address _oracle, uint32 _maxOracleDeviation, address _rateCalculator, uint64 _fullUtilizationRate, uint256 _maxLTV, uint256 _cleanLiquidationFee, uint256 _dirtyLiquidationFee, uint256 _protocolLiquidationFee)
    /// @param _immutables abi.encode(address _circuitBreakerAddress, address _comptrollerAddress, address _timelockAddress)
    /// @param _customConfigData abi.encode(string memory _nameOfContract, string memory _symbolOfContract, uint8 _decimalsOfContract)
    /// @return _pairAddress The address to which the Pair was deployed
    function _deploy(
        bytes memory _configData,
        bytes memory _immutables,
        bytes memory _customConfigData
    ) private returns (address _pairAddress) {
        // Get creation code
        bytes memory _creationCode = SSTORE2.read(contractAddress1);
        if (contractAddress2 != address(0)) {
            _creationCode = BytesLib.concat(_creationCode, SSTORE2.read(contractAddress2));
        }

        // Get bytecode
        bytes memory bytecode = abi.encodePacked(
            _creationCode,
            abi.encode(core, _configData, _immutables, _customConfigData)
        );

        // Generate salt using constructor params
        bytes32 salt = keccak256(abi.encodePacked(core, _configData, _immutables, _customConfigData));

        /// @solidity memory-safe-assembly
        assembly {
            _pairAddress := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        if (_pairAddress == address(0)) revert Create2Failed();

        return _pairAddress;
    }

    // ============================================================================================
    // Functions: External Deploy Methods
    // ============================================================================================

    /// @notice The ```deploy``` function allows the deployment of a ResupplyPair with default values
    /// @param _configData abi.encode(address _collateral, address _oracle, uint32 _maxOracleDeviation, address _rateCalculator, uint64 _fullUtilizationRate, uint256 _maxLTV, uint256 _cleanLiquidationFee, uint256 _dirtyLiquidationFee, uint256 _protocolLiquidationFee)
    /// @return _pairAddress The address to which the Pair was deployed
    function deploy(bytes memory _configData, address _underlyingStaking, uint256 _underlyingStakingId) external returns (address _pairAddress) {
        if (!operators[msg.sender]) {
            revert WhitelistedDeployersOnly();
        }

        (address _collateral,,,,,,,) = abi.decode(
            _configData,
            (address, address, address, uint256, uint256, uint256, uint256, uint256)
        );

        string memory _name = getNextName(_collateral);
        collateralId[_collateral] += 1;

        bytes memory _immutables = abi.encode(registry);
        bytes memory _customConfigData = abi.encode(_name, govToken, _underlyingStaking, _underlyingStakingId);

        _pairAddress = _deploy(_configData, _immutables, _customConfigData);

        emit LogDeploy(_pairAddress, _collateral, _name, _configData, _immutables, _customConfigData);
    }

    // ============================================================================================
    // Errors
    // ============================================================================================

    error NonUniqueName();
    error WhitelistedDeployersOnly();
    error Create2Failed();
}
