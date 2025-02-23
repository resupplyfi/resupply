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
    Protocol[] public supportedProtocols;
    mapping(
        uint256 protocolId => mapping(
        address borrowToken => mapping(
        address collateralToken => uint256 id
    ))) public collateralId;

    // immutable contracts
    address public immutable registry;
    address public immutable govToken;
    mapping(address => bool) public operators;

    struct Protocol {
        string protocolName;
        bytes4 borrowTokenSig;
        bytes4 collateralTokenSig;
    }

    event ProtocolUpdated(
        uint256 indexed protocolId,
        string protocolName, 
        bytes4 borrowTokenSig, 
        bytes4 collateralTokenSig
    );

    /// @notice Emits when a new pair is deployed
    /// @param address_ The address of the pair
    /// @param collateral The address of the Collateral Token contract
    /// @param protocolId The ID of the supported lending protocol
    /// @param name The name of the Pair
    /// @param configData The config data of the Pair
    /// @param immutables The immutables of the Pair
    /// @param customConfigData The custom config data of the Pair
    event LogDeploy(
        address indexed address_,
        address indexed collateral,
        uint256 indexed protocolId,
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
        emit SetOperator(_core, true);
        emit SetOperator(_initialoperator, true);
    }

    function version() external pure returns (uint256 _major, uint256 _minor, uint256 _patch) {
        return (1, 0, 0);
    }

    // ============================================================================================
    // Functions: View Functions
    // ============================================================================================

    /**
     * @notice Get the next name for a collateral
     * @param _protocolId The protocol ID, which must be added
     * @param _collateral The collateral address
     * @return _name The next name for the collateral following the protocol naming convention
     * @return _borrowToken The borrow token address
     * @return _collateralToken The collateral token address
     * @dev The naming convention is:
     * - Resupply Pair (Protocol: BorrowTokenSymbol/CollateralTokenSymbol) - Collateral ID
     */

    function getNextName(
        uint256 _protocolId,
        address _collateral
    ) public view returns (string memory _name, address _borrowToken, address _collateralToken) {
        uint256 length = supportedProtocols.length;
        if (_protocolId >= length) revert ProtocolNotFound();
        Protocol memory pData = supportedProtocols[_protocolId];

        // Get token addresses using protocol-specific function signatures
        (bool successBorrow, bytes memory borrowData) = _collateral.staticcall(abi.encodeWithSelector(pData.borrowTokenSig));
        (bool successCollat, bytes memory collatData) = _collateral.staticcall(abi.encodeWithSelector(pData.collateralTokenSig));
        
        require(successBorrow && borrowData.length >= 32, "Borrow token lookup failed");
        require(successCollat && collatData.length >= 32, "Collateral token lookup failed");
        
        _borrowToken = abi.decode(borrowData, (address));
        _collateralToken = abi.decode(collatData, (address));
        
        string memory borrowSymbol = IERC20(_borrowToken).safeSymbol();
        string memory collatSymbol = IERC20(_collateralToken).safeSymbol();

        uint256 _collateralId = collateralId[_protocolId][_borrowToken][_collateralToken] + 1;

        _name = string(
            abi.encodePacked(
                "Resupply Pair (",
                pData.protocolName,
                ": ",
                borrowSymbol,
                "/",
                collatSymbol,
                ") - ",
                _collateralId.toString()
            )
        );
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

    /// @notice The `addSupportedProtocol` function adds a new protocol configuration to the registry
    /// @param _protocolName The name of the protocol to add
    /// @param _borrowTokenSig The function signature used to lookup the borrow token address
    /// @param _collateralTokenSig The function signature used to lookup the collateral token address
    /// @return The ID of the newly added protocol
    function addSupportedProtocol(
        string memory _protocolName,
        bytes4 _borrowTokenSig,
        bytes4 _collateralTokenSig
    ) external onlyOwner returns (uint256) {
        if (bytes(_protocolName).length == 0) revert ProtocolNameEmpty();
        if (bytes(_protocolName).length > 50) revert ProtocolNameTooLong();
        
        // Ensure protocol name is unique
        uint256 length = supportedProtocols.length;
        for (uint256 i = 0; i < length; i++) {
            if (keccak256(bytes(supportedProtocols[i].protocolName)) == keccak256(bytes(_protocolName))) {
                revert ProtocolAlreadyExists();
            }
        }
        supportedProtocols.push(Protocol({
            protocolName: _protocolName,
            borrowTokenSig: _borrowTokenSig,
            collateralTokenSig: _collateralTokenSig
        }));
        emit ProtocolUpdated(length, _protocolName, _borrowTokenSig, _collateralTokenSig);
        return length;
    }

    function updateSupportedProtocol(
        uint256 protocolId,
        string memory _protocolName,
        bytes4 _borrowTokenSig,
        bytes4 _collateralTokenSig
    ) external onlyOwner returns (uint256) {
        if (bytes(_protocolName).length == 0) revert ProtocolNameEmpty();
        if (bytes(_protocolName).length > 50) revert ProtocolNameTooLong();
        if (protocolId >= supportedProtocols.length) revert ProtocolNotFound();
        supportedProtocols[protocolId].protocolName = _protocolName;
        supportedProtocols[protocolId].borrowTokenSig = _borrowTokenSig;
        supportedProtocols[protocolId].collateralTokenSig = _collateralTokenSig;
        emit ProtocolUpdated(protocolId, _protocolName, _borrowTokenSig, _collateralTokenSig);
        return protocolId;
    }

    function platformNameById(
        uint256 protocolId
    ) external view returns (string memory) {
        return supportedProtocols[protocolId].protocolName;
    }

    // ============================================================================================
    // Functions: Internal Methods
    // ============================================================================================

    /// @notice The ```_deploy``` function is an internal function with deploys the pair
    /// @param _configData abi.encode(address _collateral, address _oracle, address _rateCalculator, uint256 _maxLTV, uint256 _liquidationFee, uint256 _mintFee, uint256 _protocolRedemptionFee)
    /// @param _immutables abi.encode(address _registry)
    /// @param _customConfigData abi.encode(string memory _nameOfContract, address _govToken, address _underlyingStaking, uint256 _stakingId)
    /// @return _pairAddress The address to which the Pair was deployed
    function _deploy(
        bytes memory _configData,
        bytes memory _immutables,
        bytes memory _customConfigData
    ) private returns (address _pairAddress) {
        // Get creation code
        bytes memory _creationCode = SSTORE2.read(contractAddress1);
        address _contractAddress2 = contractAddress2;
        if (_contractAddress2 != address(0)) {
            _creationCode = BytesLib.concat(_creationCode, SSTORE2.read(_contractAddress2));
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
    /// @param _protocolId The ID of the supported protocol
    /// @param _configData abi.encode(address _collateral, address _oracle, address _rateCalculator, uint256 _maxLTV, uint256 _initialBorrowLimit, uint256 _liquidationFee, uint256 _mintFee, uint256 _protocolRedemptionFee)
    /// @param _underlyingStaking The address of the underlying staking contract
    /// @param _underlyingStakingId The ID of the underlying staking contract
    /// @return _pairAddress The address to which the Pair was deployed
    function deploy(uint256 _protocolId, bytes memory _configData, address _underlyingStaking, uint256 _underlyingStakingId) external returns (address _pairAddress) {
        if (!operators[msg.sender]) {
            revert WhitelistedDeployersOnly();
        }

        (address _collateral,,,,,,,) = abi.decode(
            _configData,
            (address, address, address, uint256, uint256, uint256, uint256, uint256)
        );

        (string memory _name, address _borrowToken, address _collateralToken) = getNextName(_protocolId, _collateral);
        
        collateralId[_protocolId][_borrowToken][_collateralToken]++;

        bytes memory _immutables = abi.encode(registry);
        bytes memory _customConfigData = abi.encode(_name, govToken, _underlyingStaking, _underlyingStakingId);

        _pairAddress = _deploy(_configData, _immutables, _customConfigData);

        emit LogDeploy(_pairAddress, _collateral, _protocolId, _name, _configData, _immutables, _customConfigData);
    }

    // ============================================================================================
    // Errors
    // ============================================================================================

    error NonUniqueName();
    error WhitelistedDeployersOnly();
    error Create2Failed();
    error ProtocolNotFound();
    error ProtocolNameEmpty();
    error ProtocolNameTooLong();
    error ProtocolAlreadyExists();
}
