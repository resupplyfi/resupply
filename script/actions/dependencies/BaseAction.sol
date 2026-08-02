pragma solidity 0.8.28;

import { TenderlyHelper } from "script/utils/TenderlyHelper.sol";
import { ICore } from "src/interfaces/ICore.sol";
import { Protocol, Mainnet } from "src/Constants.sol";
import { ITreasury } from "src/interfaces/ITreasury.sol";
import { Upgrades, Options } from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import { IConvexStaking } from "src/interfaces/convex/IConvexStaking.sol";
import { IResupplyPairDeployer } from "src/interfaces/IResupplyPairDeployer.sol";
import { ICurveLendV2Factory, ICurveLendV2Vault } from "src/interfaces/curve/ICurveLendV2Factory.sol";
import { ResupplyPairDeployer } from "src/protocol/ResupplyPairDeployer.sol";

contract BaseAction is TenderlyHelper {
    uint256 internal constant CURVE_LEND_V2_VAULT_TYPE = 1;
    bytes32 internal constant CURVE_LEND_V2_VERSION_HASH = keccak256("2.0.0");

    struct CurveLendV2Market {
        address factory;
        address vault;
        address borrowedToken;
        address collateralToken;
        uint256 convexPid;
    }

    address public core = Protocol.CORE;
    uint256 public epochLength;
    uint256 public startTime;
    IResupplyPairDeployer public pairDeployer = IResupplyPairDeployer(Protocol.PAIR_DEPLOYER_V2);

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

    /// @notice Builds a default-config deployment after validating its staking target.
    function getPairDeploymentAddressAndCallData(
        uint256 _protocolId,
        address _collateral,
        address _staking,
        uint256 _stakingId
    ) public view returns (address, bytes memory) {
        _validateStaking(_collateral, _staking, _stakingId);

        address predictedAddress = pairDeployer.predictPairAddress(
            _protocolId,
            _collateral,
            _staking,
            _stakingId
        );
        bytes memory callData = abi.encodeWithSelector(
            pairDeployer.deployWithDefaultConfig.selector,
            _protocolId,
            _collateral,
            _staking,
            _stakingId
        );
        return (predictedAddress, callData);
    }

    /// @notice Builds a validated LLv2 pair using today's defaults and a deliberate borrow limit.
    function _getCurveLendV2PairDeployment(
        CurveLendV2Market memory _market,
        uint256 _initialBorrowLimit
    ) internal view returns (address, bytes memory) {
        _validateCurveLendV2Market(_market);

        (address deployerBorrowedToken, address deployerCollateralToken) = pairDeployer
            .getBorrowAndCollateralTokens(Protocol.PROTOCOL_ID_CURVE_V2, _market.vault);
        require(
            deployerBorrowedToken == _market.borrowedToken,
            "Unexpected pair deployer borrowed token"
        );
        require(
            deployerCollateralToken == _market.collateralToken,
            "Unexpected pair deployer collateral token"
        );

        ResupplyPairDeployer.ConfigData memory config =
            ResupplyPairDeployer(address(pairDeployer)).defaultConfigData();
        config.initialBorrowLimit = _initialBorrowLimit;

        return _getPairDeploymentAddressAndCallData(
            Protocol.PROTOCOL_ID_CURVE_V2,
            abi.encode(
                _market.vault,
                config.oracle,
                config.rateCalculator,
                config.maxLTV,
                config.initialBorrowLimit,
                config.liquidationFee,
                config.mintFee,
                config.protocolRedemptionFee
            ),
            Mainnet.CONVEX_BOOSTER,
            _market.convexPid
        );
    }

    function _getPairDeploymentAddressAndCallData(
        uint256 _protocolId,
        bytes memory _configData,
        address _staking,
        uint256 _stakingId
    ) internal view returns (address, bytes memory) {
        (address collateral,,,,,,,) = abi.decode(
            _configData,
            (address, address, address, uint256, uint256, uint256, uint256, uint256)
        );
        _validateStaking(collateral, _staking, _stakingId);

        address predictedAddress = pairDeployer.predictPairAddress(
            _protocolId,
            _configData,
            _staking,
            _stakingId
        );
        bytes memory callData = abi.encodeWithSelector(
            pairDeployer.deploy.selector,
            _protocolId,
            _configData,
            _staking,
            _stakingId
        );
        return (predictedAddress, callData);
    }

    /// @notice Explicit trust roots for permissionless LLv2 market discovery.
    /// @dev Add future reviewed LLv2 factories here before using them in proposals.
    function _isRecognizedCurveLendV2Factory(address _factory) internal pure returns (bool) {
        return _factory == Mainnet.CURVE_LEND_V2_FACTORY;
    }

    /// @notice Proves that a proposed lender vault is a canonical market from a recognized LLv2 factory.
    function _validateCurveLendV2Market(CurveLendV2Market memory _market) internal view {
        require(
            _isRecognizedCurveLendV2Factory(_market.factory),
            "Unrecognized LLv2 factory"
        );
        require(_market.factory.code.length > 0, "LLv2 factory not deployed");
        require(_market.vault.code.length > 0, "LLv2 vault not deployed");

        ICurveLendV2Factory factory = ICurveLendV2Factory(_market.factory);
        require(
            keccak256(bytes(factory.version())) == CURVE_LEND_V2_VERSION_HASH,
            "Unsupported LLv2 factory version"
        );

        (uint256 marketIndex, uint256 contractType) = factory.check_contract(_market.vault);
        require(contractType == CURVE_LEND_V2_VAULT_TYPE, "LLv2 asset is not a factory vault");
        require(marketIndex < factory.market_count(), "Invalid LLv2 market index");

        ICurveLendV2Factory.Market memory market = factory.markets(marketIndex);
        require(market.vault == _market.vault, "LLv2 factory vault mismatch");
        require(
            market.borrowedToken == _market.borrowedToken,
            "Unexpected LLv2 borrowed token"
        );
        require(
            market.collateralToken == _market.collateralToken,
            "Unexpected LLv2 collateral token"
        );
        require(market.controller.code.length > 0, "LLv2 controller not deployed");
        require(market.amm.code.length > 0, "LLv2 AMM not deployed");
        require(market.priceOracle.code.length > 0, "LLv2 oracle not deployed");
        require(market.monetaryPolicy.code.length > 0, "LLv2 policy not deployed");

        ICurveLendV2Vault vault = ICurveLendV2Vault(_market.vault);
        require(vault.factory() == _market.factory, "Unexpected LLv2 vault factory");
        require(vault.asset() == market.borrowedToken, "LLv2 vault asset mismatch");
        require(vault.borrowed_token() == market.borrowedToken, "LLv2 vault borrowed token mismatch");
        require(vault.collateral_token() == market.collateralToken, "LLv2 vault collateral token mismatch");
        require(vault.controller() == market.controller, "LLv2 vault controller mismatch");
        require(vault.amm() == market.amm, "LLv2 vault AMM mismatch");

        _validateStaking(_market.vault, Mainnet.CONVEX_BOOSTER, _market.convexPid);
    }

    function _validateStaking(address _collateral, address _staking, uint256 _stakingId) internal view {
        if (_staking == Mainnet.CONVEX_BOOSTER) {
            (address lpToken,,,,, bool shutdown) = IConvexStaking(_staking).poolInfo(_stakingId);
            require(!shutdown, "Staking pool is shutdown");
            require(lpToken != address(0), "Invalid staking pool");
            require(lpToken == _collateral, "Staking pool collateral mismatch");
        }
    }
}
