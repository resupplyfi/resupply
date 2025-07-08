// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title ResupplyPairDeployer
 * @notice Based on code from Drake Evans and Frax Finance's pair deployer contract (https://github.com/FraxFinance/fraxlend), adapted for Resupply Finance
 */

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { CoreOwnable } from "src/dependencies/CoreOwnable.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { SSTORE2 } from "@rari-capital/solmate/src/utils/SSTORE2.sol";
import { BytesLib } from "solidity-bytes-utils/contracts/BytesLib.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { SafeERC20 } from "src/libraries/SafeERC20.sol";
import { IShareBurner } from "src/interfaces/IShareBurner.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IResupplyPairDeployer } from "src/interfaces/IResupplyPairDeployer.sol";

contract ResupplyPairDeployer is CoreOwnable {
    using Strings for uint256;
    using SafeERC20 for IERC20;

    // Storage
    address public contractAddress1;
    address public contractAddress2;
    IShareBurner public shareBurner;
    uint256 public minShareBurnAmount = 1e17;
    Protocol[] public supportedProtocols;
    mapping(
        uint256 protocolId => mapping(
        address borrowToken => mapping(
        address collateralToken => uint256 id
    ))) public collateralId;

    // immutable contracts
    address public immutable registry;
    address public immutable govToken;

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

    event ShareBurnerUpdated(address indexed _shareBurner, uint256 _minShareBurnAmount);

    constructor(address _core, address _registry, address _govToken, address _shareBurner) CoreOwnable(_core){
        registry = _registry;
        govToken = _govToken;
        shareBurner = IShareBurner(_shareBurner);
        address _previousPairDeployer = IResupplyRegistry(registry).getAddress("DEPLOYER");
        if(_previousPairDeployer != address(0)) {
            _migrateState(_previousPairDeployer);
        }
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
        (_borrowToken, _collateralToken) = getBorrowAndCollateralTokens(_protocolId, _collateral);
        require(_borrowToken != address(0) && _collateralToken != address(0), "Invalid borrow or collateral token lookup");
        
        string memory borrowSymbol = IERC20(_borrowToken).safeSymbol();
        string memory collatSymbol = IERC20(_collateralToken).safeSymbol();

        uint256 _collateralId = collateralId[_protocolId][_borrowToken][_collateralToken] + 1;

        _name = string(
            abi.encodePacked(
                "Resupply Pair (",
                supportedProtocols[_protocolId].protocolName,
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

    function getBorrowAndCollateralTokens(
        uint256 _protocolId,
        address _collateral
    ) public view returns (address _borrowToken, address _collateralToken) {
        uint256 length = supportedProtocols.length;
        if (_protocolId >= length) revert ProtocolNotFound();
        Protocol memory pData = supportedProtocols[_protocolId];

        // Get token addresses using protocol-specific function signatures
        (bool successBorrow, bytes memory borrowData) = _collateral.staticcall(abi.encodeWithSelector(pData.borrowTokenSig));
        (bool successCollat, bytes memory collatData) = _collateral.staticcall(abi.encodeWithSelector(pData.collateralTokenSig));
        
        if(successBorrow && borrowData.length >= 32) _borrowToken = abi.decode(borrowData, (address));
        if(successCollat && collatData.length >= 32) _collateralToken = abi.decode(collatData, (address));
    }

    // ============================================================================================
    // Functions: Setters
    // ============================================================================================

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

    function setShareBurner(address _shareBurner, uint256 _minShareBurnAmount) external onlyOwner {
        shareBurner = IShareBurner(_shareBurner);
        minShareBurnAmount = _minShareBurnAmount;
        emit ShareBurnerUpdated(_shareBurner, _minShareBurnAmount);
    }

    function platformNameById(
        uint256 protocolId
    ) external view returns (string memory) {
        return supportedProtocols[protocolId].protocolName;
    }

    function supportedProtocolsLength() external view returns (uint256) {
        return supportedProtocols.length;
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

    // Migrate state from previous pair deployer
    function _migrateState(address _previousPairDeployer) internal {
        if (_previousPairDeployer == address(0)) return;
        IResupplyPairDeployer _deployer = IResupplyPairDeployer(_previousPairDeployer);
        contractAddress1 = _deployer.contractAddress1();
        contractAddress2 = _deployer.contractAddress2();
        uint256 i = 0;
        while (true) {
            try _deployer.supportedProtocols(i) returns (
                string memory protocolName, bytes4 borrowTokenSig, bytes4 collateralTokenSig
            ) {
                supportedProtocols.push(Protocol({
                    protocolName: protocolName,
                    borrowTokenSig: borrowTokenSig,
                    collateralTokenSig: collateralTokenSig
                }));
                i++;
            } catch {
                break; // reached the end of the supported protocols
            }
        }
        
        // Migrate collateral IDs
        address[] memory pairs = IResupplyRegistry(registry).getAllPairAddresses();
        uint256 length = pairs.length;
        for (uint256 i = 0; i < length; i++) {
            address _pair = pairs[i];
            address _collateral = IResupplyPair(_pair).collateral();
            for (uint256 k = 0; k < supportedProtocols.length; k++) {
                (address _borrowToken, address _collateralToken) = getBorrowAndCollateralTokens(k, _collateral);
                if(_borrowToken != address(0) && _collateralToken != address(0)){
                    collateralId[k][_borrowToken][_collateralToken] = _deployer.collateralId(k, _borrowToken, _collateralToken);
                }
            }
        }
    }

    // ============================================================================================
    // Functions: External Methods
    // ============================================================================================

    /// @notice The ```deploy``` function allows the deployment of a ResupplyPair with default values
    /// @param _protocolId The ID of the supported protocol
    /// @param _configData abi.encode(address _collateral, address _oracle, address _rateCalculator, uint256 _maxLTV, uint256 _initialBorrowLimit, uint256 _liquidationFee, uint256 _mintFee, uint256 _protocolRedemptionFee)
    /// @param _underlyingStaking The address of the underlying staking contract
    /// @param _underlyingStakingId The ID of the underlying staking contract
    /// @return _pairAddress The address to which the Pair was deployed
    function deploy(uint256 _protocolId, bytes memory _configData, address _underlyingStaking, uint256 _underlyingStakingId) external onlyOwner returns (address _pairAddress) {
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

        _addPairToRegistry(_pairAddress);
        address _shareBurner = address(shareBurner);
        if (_shareBurner != address(0)) {
            shareBurner.burn();
            uint256 _balance = IERC20(_collateral).balanceOf(_shareBurner);
            require(_balance > minShareBurnAmount, "Not enough shares burned");
        }
    }

    function _addPairToRegistry(address _pairAddress) internal {
        core.execute(address(registry), abi.encodeWithSelector(IResupplyRegistry.addPair.selector, _pairAddress));
    }

    /// @notice Returns the deterministic address of a pair that would be deployed with the given parameters
    /// @dev The predicted address will change for the same parameters if a deployment occurs after the call
    /// @param _protocolId The ID of the supported protocol
    /// @param _configData abi.encode(address _collateral, address _oracle, address _rateCalculator, uint256 _maxLTV, uint256 _initialBorrowLimit, uint256 _liquidationFee, uint256 _mintFee, uint256 _protocolRedemptionFee)
    /// @param _underlyingStaking The address of the underlying staking contract
    /// @param _underlyingStakingId The ID of the underlying staking contract
    /// @return _pairAddress The predicted address of the Pair
    function predictPairAddress(
        uint256 _protocolId,
        bytes memory _configData,
        address _underlyingStaking,
        uint256 _underlyingStakingId
    ) external view returns (address) {
        (address _collateral,,,,,,,) = abi.decode(
            _configData,
            (address, address, address, uint256, uint256, uint256, uint256, uint256)
        );
        (string memory _name,,) = getNextName(_protocolId, _collateral);

        bytes memory _immutables = abi.encode(registry);
        bytes memory _customConfigData = abi.encode(
            _name,
            govToken,
            _underlyingStaking,
            _underlyingStakingId
        );

        bytes memory creationCode = SSTORE2.read(contractAddress1);
        if (contractAddress2 != address(0)) {
            creationCode = BytesLib.concat(creationCode, SSTORE2.read(contractAddress2));
        }
        bytes memory bytecode = abi.encodePacked(
            creationCode,
            abi.encode(core, _configData, _immutables, _customConfigData)
        );

        bytes32 salt = keccak256(abi.encodePacked(core, _configData, _immutables, _customConfigData));
        bytes32 _hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)));

        return address(uint160(uint256(_hash)));
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
