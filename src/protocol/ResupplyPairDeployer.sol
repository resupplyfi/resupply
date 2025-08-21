// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title ResupplyPairDeployer
 * @notice Based on code from Drake Evans and Frax Finance's pair deployer contract (https://github.com/FraxFinance/fraxlend), adapted for Resupply Finance
 */

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { CoreOwnable } from "src/dependencies/CoreOwnable.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { IResupplyPairImplementation } from "src/interfaces/IResupplyPairImplementation.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IResupplyPairDeployerDeprecated } from "src/interfaces/IResupplyPairDeployerDeprecated.sol";

contract ResupplyPairDeployer is CoreOwnable {
    using Strings for uint256;
    using SafeERC20 for IERC20;

    address public implementation;
    Protocol[] public supportedProtocols;
    mapping(address => bool) public approvedDeployers;
    mapping(address => DeployInfo) public deployInfo;
    mapping(
        uint256 protocolId => mapping(
        address borrowToken => mapping(
        address collateralToken => uint256 id
    ))) public collateralId;

    // Default Pair configuration data
    ConfigData private _defaultConfigData;

    /// @notice Get the default configuration data
    /// @return The default configuration data struct
    function defaultConfigData() external view returns (ConfigData memory) {
        return _defaultConfigData;
    }

    // immutable contracts
    address public immutable registry;
    address public immutable govToken;

    struct Protocol {
        string protocolName;
        uint80 amountToBurn;
        uint80 minShareBurnAmount;
        bytes4 borrowTokenSig;
        bytes4 collateralTokenSig;
    }

    struct ConfigData {
        address oracle;
        address rateCalculator;
        uint256 maxLTV;
        uint256 initialBorrowLimit;
        uint256 liquidationFee;
        uint256 mintFee;
        uint256 protocolRedemptionFee;
    }

    event ProtocolUpdated(
        uint256 indexed protocolId,
        string protocolName, 
        bytes4 borrowTokenSig, 
        bytes4 collateralTokenSig
    );

    event DefaultConfigDataSet(
        address oracle,
        address rateCalculator,
        uint256 maxLTV,
        uint256 initialBorrowLimit,
        uint256 liquidationFee,
        uint256 mintFee,
        uint256 protocolRedemptionFee
    );

    struct DeployInfo {
        uint40 protocolId;
        uint40 deployTime;
    }

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

    event ApprovedDeployerSet(address indexed _deployer, bool _approved);
    event StateMigrated(address indexed _previousPairDeployer);
    event ImplementationUpdated(address indexed _implementation);

    modifier onlyApprovedDeployers() {
        if(
            !approvedDeployers[msg.sender] &&
            msg.sender != owner()
        ) revert ApprovedDeployersOnly();
        _;
    }

    constructor(
        address _core, 
        address _registry, 
        address _govToken, 
        address _initialDeployer,
        address _implementation,
        ConfigData memory _defaultConfigData,
        address[] memory _previouslyDeployedPairs,
        DeployInfo[] memory _previouslyDeployedPairsInfo
    ) CoreOwnable(_core){
        require(_previouslyDeployedPairs.length == _previouslyDeployedPairsInfo.length, "lengths must match");
        registry = _registry;
        govToken = _govToken;
        implementation = _implementation;
        _setApprovedDeployer(_initialDeployer, true);
        // Set default config data
        _setDefaultConfigData(
            _defaultConfigData.oracle,
            _defaultConfigData.rateCalculator,
            _defaultConfigData.maxLTV,
            _defaultConfigData.initialBorrowLimit,
            _defaultConfigData.liquidationFee,
            _defaultConfigData.mintFee,
            _defaultConfigData.protocolRedemptionFee
        );
        if(_previouslyDeployedPairs.length > 0){
            address _previousPairDeployer = IResupplyRegistry(registry).getAddress("PAIR_DEPLOYER");
            require(_previousPairDeployer != address(0), "previous deployer not found");
            _migrateState(_previousPairDeployer, _previouslyDeployedPairs, _previouslyDeployedPairsInfo);
        }
    }

    function version() external pure returns (uint256 _major, uint256 _minor, uint256 _patch) {
        return (1, 1, 0);
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
        if(_borrowToken == address(0) || _collateralToken == address(0)) revert InvalidBorrowOrCollateralTokenLookup();
        
        string memory borrowSymbol = IERC20Metadata(_borrowToken).symbol();
        string memory collatSymbol = IERC20Metadata(_collateralToken).symbol();

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

    /// @notice The `getBorrowAndCollateralTokens` function returns the underlying borrow and collateral tokens for a particular collateral
    /// @dev This function will return address(0) or for tokens it is unable to lookup. 
    ///     Alternatively, this function may revert if the collateral contract supplied is not compliant with the expected abi.
    /// @param _protocolId The ID of the protocol to lookup
    /// @param _collateral The collateral address to lookup
    /// @return _borrowToken The borrow token address. 0x0 if unable to lookup the tokens
    /// @return _collateralToken The collateral token address. 0x0 if unable to lookup the tokens
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

    /// @notice The ```setImplementation``` function sets the implementation contract for ResupplyPair deployment
    /// @param _implementation The address of the ResupplyPairImplementation contract
    function setImplementation(address _implementation) external onlyOwner {
        require(_implementation != address(0), "Invalid implementation");
        require(_implementation.code.length > 0, "Implementation has no code");
        implementation = _implementation;
        emit ImplementationUpdated(_implementation);
    }

    /// @notice The `setDefaultConfigData` function sets the default configuration data for deployments
    /// @param _oracle The oracle address
    /// @param _rateCalculator The rate calculator address
    /// @param _maxLTV The maximum loan-to-value ratio
    /// @param _initialBorrowLimit The initial borrow limit
    /// @param _liquidationFee The liquidation fee
    /// @param _mintFee The mint fee
    /// @param _protocolRedemptionFee The protocol redemption fee
    function setDefaultConfigData(
        address _oracle,
        address _rateCalculator,
        uint256 _maxLTV,
        uint256 _initialBorrowLimit,
        uint256 _liquidationFee,
        uint256 _mintFee,
        uint256 _protocolRedemptionFee
    ) external onlyOwner {
        _setDefaultConfigData(
            _oracle,
            _rateCalculator,
            _maxLTV,
            _initialBorrowLimit,
            _liquidationFee,
            _mintFee,
            _protocolRedemptionFee
        );
    }

    /// @notice Internal function to set default configuration data
    /// @param _oracle The oracle address
    /// @param _rateCalculator The rate calculator address
    /// @param _maxLTV The maximum loan-to-value ratio
    /// @param _initialBorrowLimit The initial borrow limit
    /// @param _liquidationFee The liquidation fee
    /// @param _mintFee The mint fee
    /// @param _protocolRedemptionFee The protocol redemption fee
    function _setDefaultConfigData(
        address _oracle,
        address _rateCalculator,
        uint256 _maxLTV,
        uint256 _initialBorrowLimit,
        uint256 _liquidationFee,
        uint256 _mintFee,
        uint256 _protocolRedemptionFee
    ) internal {
        if(_oracle == address(0) || _rateCalculator == address(0)) revert InvalidConfigData();
        if(_maxLTV > 1e5) revert InvalidConfigData();
        if(_liquidationFee > 1e5) revert InvalidConfigData();
        if(_mintFee > 1e5) revert InvalidConfigData();
        if(_protocolRedemptionFee > 1e18) revert InvalidConfigData();
        _defaultConfigData = ConfigData({
            oracle: _oracle,
            rateCalculator: _rateCalculator,
            maxLTV: _maxLTV,
            initialBorrowLimit: _initialBorrowLimit,
            liquidationFee: _liquidationFee,
            mintFee: _mintFee,
            protocolRedemptionFee: _protocolRedemptionFee
        });
        
        emit DefaultConfigDataSet(
            _oracle,
            _rateCalculator,
            _maxLTV,
            _initialBorrowLimit,
            _liquidationFee,
            _mintFee,
            _protocolRedemptionFee
        );
    }

    /// @notice The `addSupportedProtocol` function adds a new protocol configuration to the registry
    /// @param _protocolName The name of the protocol to add
    /// @param _amountToBurn The amount of shares to burn on deployment
    /// @param _minShareBurnAmount The minimum amount of shares to burn on deployment
    /// @param _borrowTokenSig The function signature used to lookup the borrow token address
    /// @param _collateralTokenSig The function signature used to lookup the collateral token address
    /// @return The ID of the newly added protocol
    function addSupportedProtocol(
        string memory _protocolName,
        uint256 _amountToBurn,
        uint256 _minShareBurnAmount,
        bytes4 _borrowTokenSig,
        bytes4 _collateralTokenSig
    ) external onlyOwner returns (uint256) {
        if (_amountToBurn < 1e17 || _amountToBurn > type(uint80).max) revert InvalidAmountToBurn();
        if (_minShareBurnAmount < 1e17 || _minShareBurnAmount > type(uint80).max) revert InvalidMinShareBurnAmount();
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
            amountToBurn: uint80(_amountToBurn),
            minShareBurnAmount: uint80(_minShareBurnAmount),
            borrowTokenSig: _borrowTokenSig,
            collateralTokenSig: _collateralTokenSig
        }));
        emit ProtocolUpdated(length, _protocolName, _borrowTokenSig, _collateralTokenSig);
        return length;
    }

    function setApprovedDeployer(address _deployer, bool _approved) external onlyOwner {
        _setApprovedDeployer(_deployer, _approved);
    }

    function _setApprovedDeployer(address _deployer, bool _approved) internal {
        approvedDeployers[_deployer] = _approved;
        emit ApprovedDeployerSet(_deployer, _approved);
    }

    /// @notice The `updateSupportedProtocol` function updates the supported protocol configuration
    /// @param _protocolId The ID of the protocol to update
    /// @param _protocolName The name of the protocol to update
    /// @param _amountToBurn The amount of shares to burn on deployment
    /// @param _minShareBurnAmount The minimum amount of shares to burn on deployment
    /// @param _borrowTokenSig The function signature used to lookup the borrow token address
    function updateSupportedProtocol(
        uint256 _protocolId,
        string memory _protocolName,
        uint256 _amountToBurn,
        uint256 _minShareBurnAmount,
        bytes4 _borrowTokenSig,
        bytes4 _collateralTokenSig
    ) external onlyOwner returns (uint256) {
        if (_amountToBurn < 1e17 || _amountToBurn > type(uint80).max) revert InvalidAmountToBurn();
        if (_minShareBurnAmount < 1e17 || _minShareBurnAmount > type(uint80).max) revert InvalidMinShareBurnAmount();
        if (bytes(_protocolName).length == 0) revert ProtocolNameEmpty();
        if (bytes(_protocolName).length > 50) revert ProtocolNameTooLong();
        if (_protocolId >= supportedProtocols.length) revert ProtocolNotFound();
        
        // Ensure protocol name is unique
        uint256 length = supportedProtocols.length;
        for (uint256 i = 0; i < length; i++) {
            if (i != _protocolId && keccak256(bytes(supportedProtocols[i].protocolName)) == keccak256(bytes(_protocolName))) {
                revert ProtocolAlreadyExists();
            }
        }
        
        supportedProtocols[_protocolId].protocolName = _protocolName;
        supportedProtocols[_protocolId].amountToBurn = uint80(_amountToBurn);
        supportedProtocols[_protocolId].minShareBurnAmount = uint80(_minShareBurnAmount);
        supportedProtocols[_protocolId].borrowTokenSig = _borrowTokenSig;
        supportedProtocols[_protocolId].collateralTokenSig = _collateralTokenSig;
        emit ProtocolUpdated(_protocolId, _protocolName, _borrowTokenSig, _collateralTokenSig);
        return _protocolId;
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

    function _deploy(
        uint256 _protocolId,
        bytes memory _configData,
        address _underlyingStaking,
        uint256 _underlyingStakingId
    ) internal returns (address _pairAddress) {
        (
            address _collateral,
            address _oracle,
            address _rateCalculator,
            uint256 _maxLTV,
            uint256 _initialBorrowLimit,
            uint256 _liquidationFee,
            uint256 _mintFee,
            uint256 _protocolRedemptionFee
        ) = abi.decode(_configData, (address, address, address, uint256, uint256, uint256, uint256, uint256));

        if(_oracle == address(0) || _rateCalculator == address(0)) revert InvalidConfigData();
        if(_maxLTV > 1e5) revert InvalidConfigData();
        if(_liquidationFee > 1e5) revert InvalidConfigData();
        if(_mintFee > 1e5) revert InvalidConfigData();
        if(_protocolRedemptionFee > 1e18) revert InvalidConfigData();

        (string memory _name, address _borrowToken, address _collateralToken) = getNextName(_protocolId, _collateral);
        collateralId[_protocolId][_borrowToken][_collateralToken]++;

        bytes memory _immutables = abi.encode(registry);
        bytes memory _customConfigData = abi.encode(_name, govToken, _underlyingStaking, _underlyingStakingId);

        bytes memory _creationCode = IResupplyPairImplementation(implementation).getCreationCode();

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
        if (_pairAddress == address(0) || _pairAddress.code.length == 0) revert Create2Failed();

        deployInfo[_pairAddress] = DeployInfo({
            protocolId: uint40(_protocolId),
            deployTime: uint40(block.timestamp)
        });
        
        emit LogDeploy(_pairAddress, _collateral, _protocolId, _name, _configData, _immutables, _customConfigData);

        // Burn shares
        _burnShares(
            _borrowToken, 
            _collateral, 
            supportedProtocols[_protocolId].amountToBurn, 
            supportedProtocols[_protocolId].minShareBurnAmount
        );

        return _pairAddress;
    }

    function _burnShares(address _borrowToken, address _collateral, uint256 _amountToBurn, uint256 _minShareBurnAmount) internal {
        uint256 _balanceBefore = IERC20(_collateral).balanceOf(address(0xdead));
        IERC20(_borrowToken).forceApprove(address(_collateral), _amountToBurn);
        IERC4626(_collateral).deposit(_amountToBurn, address(0xdead));
        uint256 _balanceDelta = IERC20(_collateral).balanceOf(address(0xdead)) - _balanceBefore;
        if(_balanceDelta < _minShareBurnAmount) revert NotEnoughSharesBurned();
    }

    // Migrate state from previous pair deployer
    function _migrateState(address _previousPairDeployer, address[] memory _previouslyDeployedPairs, DeployInfo[] memory _previouslyDeployedPairsInfo) internal {
        IResupplyPairDeployerDeprecated _deployer = IResupplyPairDeployerDeprecated(_previousPairDeployer);
        // Note: implementation address should be set in constructor, not migrated
        uint256 i = 0;
        // Migrate supported protocols
        while(true) {
            try _deployer.supportedProtocols(i) returns (
                string memory protocolName, bytes4 borrowTokenSig, bytes4 collateralTokenSig
            ) {
                supportedProtocols.push(Protocol({
                    protocolName: protocolName,
                    amountToBurn: 1e18,
                    minShareBurnAmount: i == 0 ? 1e20 : 1e17,
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
        require(length == _previouslyDeployedPairs.length, "lengths must match");
        for (uint256 i = 0; i < length; i++) {
            require(pairs[i] == _previouslyDeployedPairs[i], "pair mismatch");
            address _pair = pairs[i];
            address _collateral = IResupplyPair(_pair).collateral();
            DeployInfo memory _deployInfo = _previouslyDeployedPairsInfo[i];
            uint256 protocolId = _deployInfo.protocolId;
            (address _borrowToken, address _collateralToken) = getBorrowAndCollateralTokens(protocolId, _collateral);
            require(_borrowToken != address(0) && _collateralToken != address(0), "invalid protocol id");
            collateralId[protocolId][_borrowToken][_collateralToken] = _deployer.collateralId(protocolId, _borrowToken, _collateralToken);
            require(_deployInfo.deployTime > 0, "deploy time not set");
            deployInfo[_pair] = DeployInfo({
                protocolId: uint40(protocolId),
                deployTime: uint40(_deployInfo.deployTime)
            });
        }
        emit StateMigrated(_previousPairDeployer);
    }

    // ============================================================================================
    // Functions: External Methods
    // ============================================================================================

    /// @notice The ```deploy``` function allows the deployment of a ResupplyPair with custom config data
    /// @dev Custom config deployments are available to owner only. Approved deployers must use default config.
    /// @dev Each deployment also registers the pair in the registry, activating the specified borrow limit.
    /// @param _protocolId The ID of the supported protocol
    /// @param _configData abi.encode(address _collateral, address _oracle, address _rateCalculator, uint256 _maxLTV, uint256 _initialBorrowLimit, uint256 _liquidationFee, uint256 _mintFee, uint256 _protocolRedemptionFee)
    /// @param _underlyingStaking The address of the underlying staking contract
    /// @param _underlyingStakingId The ID of the underlying staking contract
    /// @return _pairAddress The address to which the Pair was deployed
    function deploy(
        uint256 _protocolId,
        bytes memory _configData,
        address _underlyingStaking,
        uint256 _underlyingStakingId
    ) external onlyOwner returns (address _pairAddress) {
        _pairAddress = _deploy(_protocolId, _configData, _underlyingStaking, _underlyingStakingId);
    }

    /// @notice This ```deploy``` function allows the deployment of a ResupplyPair using default config data
    /// @dev All deployments by approved deployers use default config.
    /// @dev Each deployment also registers the pair in the registry, activating the specified borrow limit.
    /// @param _protocolId The ID of the supported protocol
    /// @param _collateral The address of the collateral token
    /// @param _underlyingStaking The address of the underlying staking contract
    /// @param _underlyingStakingId The ID of the underlying staking contract
    /// @return _pairAddress The address to which the Pair was deployed
    function deployWithDefaultConfig(
        uint256 _protocolId,
        address _collateral,
        address _underlyingStaking,
        uint256 _underlyingStakingId
    ) external onlyApprovedDeployers returns (address _pairAddress) {
        bytes memory _configData = abi.encode(
            _collateral,
            _defaultConfigData.oracle,
            _defaultConfigData.rateCalculator,
            _defaultConfigData.maxLTV,
            _defaultConfigData.initialBorrowLimit,
            _defaultConfigData.liquidationFee,
            _defaultConfigData.mintFee,
            _defaultConfigData.protocolRedemptionFee
        );

        _pairAddress = _deploy(_protocolId, _configData, _underlyingStaking, _underlyingStakingId);
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
    ) public view returns (address) {
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
        bytes memory creationCode = IResupplyPairImplementation(implementation).getCreationCode();
        bytes memory bytecode = abi.encodePacked(
            creationCode,
            abi.encode(core, _configData, _immutables, _customConfigData)
        );
        bytes32 salt = keccak256(abi.encodePacked(core, _configData, _immutables, _customConfigData));
        bytes32 _hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)));
        return address(uint160(uint256(_hash)));
    }

    /// @notice Returns the deterministic address of a deployed pair using default config data
    /// @dev The predicted address will change for the same parameters if a deployment occurs after the call
    /// @param _protocolId The ID of the supported protocol
    /// @param _collateral The address of the collateral token
    /// @param _underlyingStaking The address of the underlying staking contract
    /// @param _underlyingStakingId The ID of the underlying staking contract
    /// @return _pairAddress The predicted address of the Pair
    function predictPairAddress(
        uint256 _protocolId,
        address _collateral,
        address _underlyingStaking,
        uint256 _underlyingStakingId
    ) external view returns (address) {        
        bytes memory _configData = abi.encode(
            _collateral,
            _defaultConfigData.oracle,
            _defaultConfigData.rateCalculator,
            _defaultConfigData.maxLTV,
            _defaultConfigData.initialBorrowLimit,
            _defaultConfigData.liquidationFee,
            _defaultConfigData.mintFee,
            _defaultConfigData.protocolRedemptionFee
        );
        return predictPairAddress(_protocolId, _configData, _underlyingStaking, _underlyingStakingId);
    }

    // ============================================================================================
    // Errors
    // ============================================================================================

    error NonUniqueName();
    error ApprovedDeployersOnly();
    error Create2Failed();
    error ProtocolNotFound();
    error ProtocolNameEmpty();
    error ProtocolNameTooLong();
    error ProtocolAlreadyExists();
    error NotEnoughSharesBurned();
    error InvalidBorrowOrCollateralTokenLookup();
    error InvalidAmountToBurn();
    error InvalidMinShareBurnAmount();
    error InvalidConfigData();
}
