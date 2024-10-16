// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "../helpers/Helpers.sol";
import "src/interfaces/IStableSwap.sol";
import "src/interfaces/IVariableInterestRateV2.sol";
import "src/interfaces/IWstEth.sol";
import "src/interfaces/IOracle.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "src/protocol/fraxlend/FraxlendPairConstants.sol";
import "src/protocol/fraxlend/FraxlendPairAccessControlErrors.sol";
import "src/protocol/BasicVaultOracle.sol";
import { RelendPairDeployer } from "src/protocol/RelendPairDeployer.sol";
import { RelendPairRegistry } from "src/protocol/RelendPairRegistry.sol";
import { InterestRateCalculator } from "src/protocol/InterestRateCalculator.sol";
import { FraxlendPair } from "src/protocol/fraxlend/FraxlendPair.sol";
import "src/Constants.sol" as Constants;
import "frax-std/FraxTest.sol";
// import "frax-std/NumberFormat.sol";
// import "frax-std/Logger.sol";
// import "frax-std/StringsHelper.sol";
// import "frax-std/oracles/OracleHelper.sol";
// import "frax-std/ArrayHelper.sol";

struct CurrentRateInfo {
    uint32 lastBlock;
    uint32 feeToProtocolRate; // Fee amount 1e5 precision
    uint64 lastTimestamp;
    uint64 ratePerSec;
    uint64 fullUtilizationRate;
}

contract BasePairTest is
    FraxlendPairConstants,
    FraxlendPairAccessControlErrors,
    TestHelper,
    // Constants.Helper,
    FraxTest
{
    using stdStorage for StdStorage;
    // using OracleHelper for AggregatorV3Interface;
    using SafeCast for uint256;
    using Strings for uint256;
    using RelendPairTestHelper for FraxlendPair;
    using NumberFormat for *;
    using StringsHelper for *;

    // contracts
    FraxlendPair public pair;
    RelendPairDeployer public deployer;
    RelendPairRegistry public pairRegistry;
    // FraxlendPairHelper public fraxlendPairHelper;
    IERC20 public asset;
    IERC20 public collateral;
    // VariableInterestRate public variableRateContract;
    InterestRateCalculator public rateContract;

    // FraxlendWhitelist public fraxlendWhitelist;

    IOracle public oracle;
    uint256 public uniqueId;

    struct UserAccounting {
        address _address;
        uint256 borrowShares;
        uint256 borrowAmountFalse;
        uint256 borrowAmountTrue;
        uint256 collateralBalance;
        uint256 balanceOfAsset;
        uint256 balanceOfCollateral;
    }

    struct PairAccounting {
        address fraxlendPairAddress;
        uint256 claimableFees;
        uint128 totalBorrowAmount;
        uint128 totalBorrowShares;
        uint256 totalCollateral;
        uint256 balanceOfAsset;
        uint256 balanceOfCollateral;
        uint128 assetShares;
        uint128 assetAmountFalse;
        uint128 assetAmountTrue;
        uint256 collateralBalance;
    }

    PairAccounting public initial;
    PairAccounting public final_;
    PairAccounting public net;

    // Users
    address[] public users = [vm.addr(1), vm.addr(2), vm.addr(3), vm.addr(4), vm.addr(5)];

    // Deployer constants
    uint256 internal constant DEFAULT_MAX_LTV = 75_000; // 75% with 1e5 precision
    uint256 internal constant DEFAULT_LIQ_FEE = 500; // 5% with 1e5 precision
    uint256 internal constant DEFAULT_PROTOCOL_LIQ_FEE = 200; // 2% of fee total collateral
    uint64 internal constant DEFAULT_MIN_INTEREST = 158_247_046;
    uint64 internal constant DEFAULT_MAX_INTEREST = 146_248_476_607;
    uint64 internal constant FIFTY_BPS = 158_247_046;
    uint64 internal constant ONE_PERCENT = FIFTY_BPS * 2;
    uint64 internal constant ONE_BPS = FIFTY_BPS / 50;

    // Interest Helpers
    uint256 internal constant ONE_PERCENT_ANNUAL_RATE = 315_315_588;

    // ============================================================================================
    // Snapshots
    // ============================================================================================

    function initialUserAccountingSnapshot(
        FraxlendPair _relendPair,
        address _userAddress
    ) public view returns (UserAccounting memory) {
        (uint256 _borrowShares, uint256 _collateralBalance) = _relendPair.getUserSnapshot(
            _userAddress
        );
        return
            UserAccounting({
                _address: _userAddress,
                borrowShares: _borrowShares,
                borrowAmountFalse: toBorrowAmount(_relendPair, _borrowShares, false),
                borrowAmountTrue: toBorrowAmount(_relendPair, _borrowShares, true),
                collateralBalance: _collateralBalance,
                balanceOfAsset: IERC20(_relendPair.asset()).balanceOf(_userAddress),
                balanceOfCollateral: IERC20(address(_relendPair.collateralContract())).balanceOf(_userAddress)
            });
    }

    function finalUserAccountingSnapshot(
        FraxlendPair _relendPair,
        UserAccounting memory _initial
    ) public view returns (UserAccounting memory _final, UserAccounting memory _net) {
        address _userAddress = _initial._address;
        (uint256 _borrowShares, uint256 _collateralBalance) = _relendPair.getUserSnapshot(
            _userAddress
        );
        _final = UserAccounting({
            _address: _userAddress,
            borrowShares: _borrowShares,
            borrowAmountFalse: toBorrowAmount(_relendPair, _borrowShares, false),
            borrowAmountTrue: toBorrowAmount(_relendPair, _borrowShares, true),
            collateralBalance: _collateralBalance,
            balanceOfAsset: IERC20(_relendPair.asset()).balanceOf(_userAddress),
            balanceOfCollateral: IERC20(address(_relendPair.collateralContract())).balanceOf(_userAddress)
        });
        _net = UserAccounting({
            _address: _userAddress,
            borrowShares: stdMath.delta(_initial.borrowShares, _final.borrowShares),
            borrowAmountFalse: stdMath.delta(_initial.borrowAmountFalse, _final.borrowAmountFalse),
            borrowAmountTrue: stdMath.delta(_initial.borrowAmountTrue, _final.borrowAmountTrue),
            collateralBalance: stdMath.delta(_initial.collateralBalance, _final.collateralBalance),
            balanceOfAsset: stdMath.delta(_initial.balanceOfAsset, _final.balanceOfAsset),
            balanceOfCollateral: stdMath.delta(_initial.balanceOfCollateral, _final.balanceOfCollateral)
        });
    }

    function takeInitialAccountingSnapshot(
        FraxlendPair _relendPair
    ) internal view returns (PairAccounting memory _initial) {
        address _fraxlendPairAddress = address(_relendPair);
        IERC20 _asset = IERC20(_relendPair.asset());
        IERC20 _collateral = _relendPair.collateralContract();

        (
            uint256 _claimableFees,
            uint128 _totalBorrowAmount,
            uint128 _totalBorrowShares,
            uint256 _totalCollateral
        ) = _relendPair.__getPairAccounting();
        _initial.fraxlendPairAddress = _fraxlendPairAddress;
        _initial.claimableFees = _claimableFees;
        _initial.totalBorrowAmount = _totalBorrowAmount;
        _initial.totalBorrowShares = _totalBorrowShares;
        _initial.totalCollateral = _totalCollateral;
        _initial.balanceOfAsset = _asset.balanceOf(_fraxlendPairAddress);
        _initial.balanceOfCollateral = _collateral.balanceOf(_fraxlendPairAddress);
        _initial.collateralBalance = _relendPair.userCollateralBalance(_fraxlendPairAddress);
    }

    function takeFinalAccountingSnapshot(
        PairAccounting memory _initial
    ) internal view returns (PairAccounting memory _final, PairAccounting memory _net) {
        address _fraxlendPairAddress = _initial.fraxlendPairAddress;
        FraxlendPair _fraxlendPair = FraxlendPair(_fraxlendPairAddress);
        IERC20 _asset = IERC20(_fraxlendPair.asset());
        IERC20 _collateral = _fraxlendPair.collateralContract();

        (
            uint256 _claimableFees,
            uint128 _totalBorrowAmount,
            uint128 _totalBorrowShares,
            uint256 _totalCollateral
        ) = _fraxlendPair.getPairAccounting();
        // Sorry for mutation syntax
        _final.fraxlendPairAddress = _fraxlendPairAddress;
        _final.claimableFees = _claimableFees;
        _final.totalBorrowAmount = _totalBorrowAmount;
        _final.totalBorrowShares = _totalBorrowShares;
        _final.totalCollateral = _totalCollateral;
        _final.balanceOfAsset = _asset.balanceOf(_fraxlendPairAddress);
        _final.balanceOfCollateral = _collateral.balanceOf(_fraxlendPairAddress);
        _final.collateralBalance = _fraxlendPair.userCollateralBalance(_fraxlendPairAddress);

        _net.fraxlendPairAddress = _fraxlendPairAddress;
        _net.claimableFees = stdMath.delta(_final.claimableFees, _initial.claimableFees).toUint128();
        _net.totalBorrowAmount = stdMath.delta(_final.totalBorrowAmount, _initial.totalBorrowAmount).toUint128();
        _net.totalBorrowShares = stdMath.delta(_final.totalBorrowShares, _initial.totalBorrowShares).toUint128();
        _net.totalCollateral = stdMath.delta(_final.totalCollateral, _initial.totalCollateral);
        _net.balanceOfAsset = stdMath.delta(_final.balanceOfAsset, _initial.balanceOfAsset);
        _net.balanceOfCollateral = stdMath.delta(_final.balanceOfCollateral, _initial.balanceOfCollateral);
        _net.collateralBalance = stdMath.delta(_final.collateralBalance, _initial.collateralBalance).toUint128();
    }

    function assertPairAccountingCorrect() public {
        // require(1 == 2, "This is a test function with a very long reason string that should be truncated");
        uint256 _totalUserBorrowShares = pair.userBorrowShares(address(pair));
        uint256 _totalUserCollateralBalance = pair.userCollateralBalance(address(pair));
       // uint256 _totalUserAssetShares = pair.balanceOf(address(pair));

        for (uint256 i = 0; i < users.length; i++) {
            _totalUserBorrowShares += pair.userBorrowShares(users[i]);
            _totalUserCollateralBalance += pair.userCollateralBalance(users[i]);
            // _totalUserAssetShares += pair.balanceOf(users[i]);
        }

        (uint128 _pairTotalBorrowAmount, uint128 _pairTotalBorrowShares) = pair.totalBorrow();
        // (uint128 _pairTotalAssetAmount, uint128 _pairTotalAssetShares) = pair.totalAsset();
        assertEq(
            _totalUserBorrowShares,
            _pairTotalBorrowShares,
            "Sum of users borrow shares equals accounting borrow shares"
        );
        assertEq(
            _totalUserCollateralBalance,
            pair.totalCollateral(),
            "Sum of users collateral balance equals total collateral accounting"
        );
        // assertEq(
        //     _totalUserAssetShares,
        //     _pairTotalAssetShares,
        //     "Sum of users asset shares equals total asset shares accounting"
        // );
        assertEq(
            pair.totalCollateral(),
            collateral.balanceOf(address(pair)),
            "Total collateral accounting matches collateral.balanceOf"
        );
        // assertEq(
        //     _pairTotalAssetAmount - _pairTotalBorrowAmount,
        //     asset.balanceOf(address(pair)),
        //     "Total collateral accounting matches collateral.balanceOf"
        // );
    }

    function assertUnwind(FraxlendPair _pair) public {
        IERC20 _asset = IERC20(_pair.asset());
        for (uint256 i = 0; i < users.length; i++) {
            address _user = users[i];
            startHoax(_user);
            uint256 _borrowShares = _pair.userBorrowShares(_user);
            uint256 _borrowAmount = _pair.toBorrowAmount(_borrowShares, true, false);
            uint256 _collateralBalance = _pair.userCollateralBalance(_user);
            faucetFunds(_asset, _borrowAmount, _user);
            _asset.approve(address(_pair), _borrowAmount);
            _pair.repayAsset(_borrowShares, _user);
            _pair.removeCollateral(_collateralBalance, _user);
            vm.stopPrank();
        }

        //todo
        // for (uint256 i = 0; i < users.length; i++) {
        //     address _user = users[i];
        //     startHoax(_user);
        //     uint256 _shares = _pair.balanceOf(_user);
        //     _pair.redeem(_shares, _user, _user);
        //     vm.stopPrank();
        // }
    }

    // ============================================================================================
    // Setup / Initial Environment Helpers
    // ============================================================================================

    // function setWhitelistTrue() public {
    //     // Deployers to whitelist
    //     address[] memory _deployerAddresses = new address[](1);
    //     _deployerAddresses[0] = Constants.Mainnet.COMPTROLLER_ADDRESS;
    //     fraxlendWhitelist.setFraxlendDeployerWhitelist(_deployerAddresses, true);
    // }

    /// @notice The ```deployNonDynamicExternalContracts``` function deploys all contracts other than the pairs using default values
    /// @dev
    function deployNonDynamicExternalContracts() public {
        /*
        1. Deploys Helper
        2. Connects whitelist
        3. Whitelists the comptroller and address(this) for deployers
        4. Deploys Registry
        5. Deploys Deployer
        6. Registers the deployer on the registry
        7. Sets Creation code from current fraxlendPair
        8. Deploys a hybrid rate calculator setup as linear rate
        9. Deploys a hybrid rate calculator setup as variable rate
        */

        // Set code for Whitelist
        // fraxlendWhitelist = FraxlendWhitelist(Constants.Mainnet.FRAXLEND_WHITELIST_ADDRESS);
        // fraxlendPairHelper = new FraxlendPairHelper();
        // setSingleDeployerWhitelist(Constants.Mainnet.COMPTROLLER_ADDRESS, true);
        // setSingleDeployerWhitelist(address(this), true);
        pairRegistry = new RelendPairRegistry(Constants.Mainnet.COMPTROLLER_ADDRESS);
        // deployer = new FraxlendPairDeployer(
        //     FraxlendPairDeployerParams({
        //         circuitBreaker: Constants.Mainnet.CIRCUIT_BREAKER_ADDRESS,
        //         comptroller: Constants.Mainnet.COMPTROLLER_ADDRESS,
        //         timelock: Constants.Mainnet.TIMELOCK_ADDRESS,
        //         fraxlendWhitelist: address(fraxlendWhitelist),
        //         fraxlendPairRegistry: address(fraxlendPairRegistry)
        //     })
        // );
        deployer = new RelendPairDeployer(
            address(pairRegistry),
            address(Constants.Mainnet.COMPTROLLER_ADDRESS),
            address(Constants.Mainnet.COMPTROLLER_ADDRESS)
        );
        address[] memory _deployers = new address[](1);
        _deployers[0] = address(deployer);
        // pairRegistry.setDeployers(_deployers, true);
        deployer.setCreationCode(type(FraxlendPair).creationCode);
        uint256 _vertexUtilization = 80_000; // 80%
        uint256 _vertexInterestPercentOfMax = 1e17; // 10%

        uint256 _minUtil = 75_000;
        uint256 _maxUtil = 85_000;
        uint64 _minInterest = 158_247_046; // 50bps
        uint64 _maxInterest = 146_248_476_607; // 10k %
        uint256 _rateHalfLife = 4 days;


        rateContract = new InterestRateCalculator(
            "suffix",
            32_000_000_000, //2% todo check
            2
        );
        // variableRateContract = new VariableInterestRate(
        //     "suffix",
        //     _vertexUtilization,
        //     _vertexInterestPercentOfMax,
        //     _minUtil,
        //     _maxUtil,
        //     _minInterest,
        //     _minInterest,
        //     _maxInterest,
        //     _rateHalfLife
        // );

        // linearRateContract = new VariableInterestRate(
        //     "suffix",
        //     _vertexUtilization,
        //     _vertexInterestPercentOfMax,
        //     0,
        //     1e5,
        //     79_123_523, // 0.25%
        //     79_123_523, // 0.25%
        //     79_123_523 * 400, // 0.25% * 400 = 100%
        //     _rateHalfLife
        // );
    }

    function deployDefaultOracle() public returns (IOracle _oracle) {
        _oracle = IOracle(
            address(
                new BasicVaultOracle(
                    "Basic Vault Oracle"
                )
            )
        );
    }

    function setExternalContracts() public {
        startHoax(Constants.Mainnet.COMPTROLLER_ADDRESS);
        deployNonDynamicExternalContracts();
        vm.stopPrank();
        // Deploy contracts
        collateral = IERC20(Constants.Mainnet.WETH_ERC20);
        asset = IERC20(Constants.Mainnet.FRAX_ERC20);
        oracle = IOracle(
            address(
                new BasicVaultOracle(
                    "Basic Vault Oracle"
                )
            )
        );
    }

    /// @notice The ```defaultSetUp``` function provides a full default deployment environment for testing
    function defaultSetUp() public virtual {
        setExternalContracts();
        startHoax(Constants.Mainnet.COMPTROLLER_ADDRESS);
        // setWhitelistTrue();
        // Set initial oracle prices
        // setSingleDeployerWhitelist(address(this), true);
        // setSingleDeployerWhitelist(Constants.Mainnet.COMPTROLLER_ADDRESS, true);
        vm.stopPrank();
        deployFraxlendPublic(address(rateContract), 25 * ONE_PERCENT);
    }

    // ============================================================================================
    // Whitelist Helpers
    // ============================================================================================

    // function setSingleDeployerWhitelist(address _address, bool _bool) public {
    //     address[] memory _addresses = new address[](1);
    //     _addresses[0] = _address;
    //     fraxlendWhitelist.setFraxlendDeployerWhitelist(_addresses, _bool);
    // }

    // ============================================================================================
    // Deployment Helpers
    // ============================================================================================

    /// @notice The ```deployFraxlendPublic``` function helps deploy Fraxlend public pairs with default config
    function deployFraxlendPublic(address _rateContract, uint64 _initialMaxRate) public {
        address _pairAddress = deployer.deploy(
            abi.encode(
                address(asset),
                address(collateral),
                address(oracle),
                uint32(5e3),
                address(_rateContract),
                _initialMaxRate,
                75_000, //75%
                10_000 // 10% clean liquidation fee
            ),
            uniqueId
        );
        uniqueId += 1;
        pair = FraxlendPair(_pairAddress);

        startHoax(Constants.Mainnet.COMPTROLLER_ADDRESS);
        pair.setSwapper(Constants.Mainnet.UNIV2_ROUTER, true);
        vm.stopPrank();

        // startHoax(Constants.Mainnet.TIMELOCK_ADDRESS);
        // pair.changeFee(uint16((10 * FEE_PRECISION) / 100));
        // vm.stopPrank();
    }

    function _encodeConfigData(
        address _rateContract,
        uint64 _fullUtilizationRate,
        uint256 _maxLTV,
        uint256 _liquidationFee,
        uint256 _protocolLiquidationFee
    ) internal view returns (bytes memory _configData) {
        _configData = abi.encode(
            address(asset),
            address(collateral),
            address(oracle),
            uint32(5e3),
            address(_rateContract),
            _fullUtilizationRate,
            _maxLTV, //75%
            _liquidationFee,
            _protocolLiquidationFee
        );
    }

    function deployFraxlendCustom(
        address _rateContractAddress,
        uint256 _maxLTV,
        uint256 _liquidationFee,
        uint256 _protocolLiquidationFee
    ) public {
        startHoax(Constants.Mainnet.COMPTROLLER_ADDRESS);
        {
            pair = FraxlendPair(
                deployer.deploy(
                    _encodeConfigData(
                        _rateContractAddress,
                        25 * ONE_PERCENT,
                        _maxLTV,
                        _liquidationFee,
                        _protocolLiquidationFee
                    ),
                    uniqueId
                )
            );
            uniqueId += 1;
        }
        vm.stopPrank();

        startHoax(Constants.Mainnet.COMPTROLLER_ADDRESS);
        pair.setSwapper(Constants.Mainnet.UNIV2_ROUTER, true);
        vm.stopPrank();

        // startHoax(Constants.Mainnet.TIMELOCK_ADDRESS);
        // pair.changeFee(uint16((10 * FEE_PRECISION) / 100));
        // vm.stopPrank();
    }

    // ============================================================================================
    // Pair View Helpers
    // ============================================================================================

    // helper to convert assets shares to amount
    // function toAssetAmount(uint256 _shares, bool roundup) public view returns (uint256 _amount) {
    //     (uint256 _amountTotal, uint256 _sharesTotal) = pair.totalAsset();
    //     _amount = toAssetAmount(_amountTotal, _sharesTotal, _shares, roundup);
    // }

    // function toAssetAmount(
    //     FraxlendPair _fraxlendPair,
    //     uint256 _shares,
    //     bool roundup
    // ) public view returns (uint256 _amount) {
    //     (uint256 _amountTotal, uint256 _sharesTotal) = _fraxlendPair.totalAsset();
    //     _amount = toAssetAmount(_amountTotal, _sharesTotal, _shares, roundup);
    // }

    // // helper to convert assets shares to amount
    // function toAssetAmount(
    //     uint256 _amountTotal,
    //     uint256 _sharesTotal,
    //     uint256 _shares,
    //     bool roundup
    // ) public pure returns (uint256 _amount) {
    //     if (_sharesTotal == 0) {
    //         _amount = _shares;
    //     } else {
    //         _amount = (_shares * _amountTotal) / _sharesTotal;
    //         if (roundup && (_amount * _sharesTotal) / _amountTotal < _shares) {
    //             _amount++;
    //         }
    //     }
    // }

    // helper to convert borrows shares to amount
    function toBorrowAmount(uint256 _shares, bool roundup) public view returns (uint256 _amount) {
        (uint256 _amountTotal, uint256 _sharesTotal) = pair.totalBorrow();
        _amount = toBorrowAmount(_amountTotal, _sharesTotal, _shares, roundup);
    }

    function toBorrowAmount(
        FraxlendPair _fraxlendPair,
        uint256 _shares,
        bool roundup
    ) public view returns (uint256 _amount) {
        (uint256 _amountTotal, uint256 _sharesTotal) = _fraxlendPair.totalBorrow();
        _amount = toBorrowAmount(_amountTotal, _sharesTotal, _shares, roundup);
    }

    // helper to convert borrows shares to amount
    function toBorrowAmount(
        uint256 _amountTotal,
        uint256 _sharesTotal,
        uint256 _shares,
        bool roundup
    ) public pure returns (uint256 _amount) {
        if (_sharesTotal == 0) {
            _amount = _shares;
        } else {
            _amount = (_shares * _amountTotal) / _sharesTotal;
            if (roundup && (_amount * _sharesTotal) / _amountTotal < _shares) {
                _amount++;
            }
        }
    }

    // // helper to convert asset amount to shares
    // function toAssetShares(uint256 _amount, bool roundup) public view returns (uint256 _shares) {
    //     (uint256 _amountTotal, uint256 _sharesTotal) = pair.totalAsset();
    //     _shares = toAssetShares(_amountTotal, _sharesTotal, _amount, roundup);
    // }

    // // helper to convert asset amount to shares
    // function toAssetShares(
    //     uint256 _amountTotal,
    //     uint256 _sharesTotal,
    //     uint256 _amount,
    //     bool roundup
    // ) public pure returns (uint256 _shares) {
    //     if (_amountTotal == 0) {
    //         _shares = _amount;
    //     } else {
    //         _shares = (_amount * _sharesTotal) / _amountTotal;
    //         if (roundup && (_shares * _amountTotal) / _sharesTotal < _amount) {
    //             _shares++;
    //         }
    //     }
    // }

    // helper to convert borrow amount to shares
    function toBorrowShares(uint256 _amount, bool roundup) public view returns (uint256 _shares) {
        (uint256 _amountTotal, uint256 _sharesTotal) = pair.totalBorrow();
        _shares = toBorrowShares(_amountTotal, _sharesTotal, _amount, roundup);
    }

    // helper to convert borrow amount to shares
    function toBorrowShares(
        uint256 _amountTotal,
        uint256 _sharesTotal,
        uint256 _amount,
        bool roundup
    ) public pure returns (uint256 _shares) {
        if (_amountTotal == 0) {
            _shares = _amount;
        } else {
            _shares = (_amount * _sharesTotal) / _amountTotal;
            if (roundup && (_shares * _amountTotal) / _sharesTotal < _amount) {
                _shares++;
            }
        }
    }

    function getUtilization() internal view returns (uint256 _utilization) {
        (uint256 _borrowAmount, ) = pair.totalBorrow();
        uint256 _borrowLimit = pair.borrowLimit();
        _utilization = (_borrowAmount * UTIL_PREC) / _borrowLimit;
    }

    function ratePerSec(FraxlendPair _pair) internal view returns (uint64 _ratePerSec) {
        (, , _ratePerSec,, ) = _pair.currentRateInfo();
    }

    function feeToProtocolRate(FraxlendPair _pair) internal view returns (uint64 _feeToProtocolRate) {
        (, _feeToProtocolRate, , , ) = _pair.currentRateInfo();
    }

    function getCollateralAmount(
        uint256 _borrowAmount,
        uint256 _exchangeRate,
        uint256 _targetLTV
    ) internal pure returns (uint256 _collateralAmount) {
        _collateralAmount = (_borrowAmount * _exchangeRate * LTV_PRECISION) / (_targetLTV * EXCHANGE_PRECISION);
    }

    // ============================================================================================
    // Pair Action Helpers
    // ============================================================================================

    // helper to faucet funds to ERC20 contracts if no users give to all
    function faucetFunds(IERC20 _contract, uint256 _amount) internal {
        uint256 _length = users.length; // gas savings, good habit
        for (uint256 i = 0; i < _length; i++) {
            faucetFunds(_contract, _amount, users[i]);
        }
    }

    struct DepositAction {
        address user;
        uint256 amount;
    }

    struct MintAction {
        address user;
        uint256 shares;
    }

    // function _preMintFaucetApprove(FraxlendPair _fraxlendPair, MintAction memory _mintAction) internal {
    //     IERC20 _asset = IERC20(_fraxlendPair.asset());
    //     uint256 _amount = _fraxlendPair.previewMint(_mintAction.shares);
    //     faucetFunds(_asset, _amount, _mintAction.user);
    //     _asset.approve(address(_fraxlendPair), _amount);
    // }

    // function lendTokenViaMintWithFaucet(FraxlendPair _pair, MintAction memory _mintAction) internal returns (uint256) {
    //     startHoax(_mintAction.user);
    //     _preMintFaucetApprove(_pair, _mintAction);
    //     uint256 _amount = _pair.mint(_mintAction.shares, _mintAction.user);
    //     vm.stopPrank();
    //     return _amount;
    // }

    // function _preDepositFaucetApprove(FraxlendPair _fraxlendPair, DepositAction memory _depositAction) internal {
    //     IERC20 _asset = IERC20(_fraxlendPair.asset());
    //     faucetFunds(_asset, _depositAction.amount, _depositAction.user);
    //     _asset.approve(address(_fraxlendPair), _depositAction.amount);
    // }

    // helper to approve and lend in one step
    // function lendTokenViaDeposit(FraxlendPair _pair, DepositAction memory _depositAction) internal returns (uint256) {
    //     startHoax(_depositAction.user);
    //     IERC20(_pair.asset()).approve(address(_pair), _depositAction.amount);
    //     uint256 _shares = _pair.deposit(_depositAction.amount, _depositAction.user);
    //     vm.stopPrank();
    //     return _shares;
    // }

    // function lendTokenViaDepositWithFaucet(
    //     FraxlendPair _pair,
    //     DepositAction memory _depositAction
    // ) internal returns (uint256) {
    //     faucetFunds(IERC20(_pair.asset()), _depositAction.amount, _depositAction.user);
    //     return lendTokenViaDeposit(_pair, _depositAction);
    // }

    // Borrowing

    struct BorrowAction {
        address user;
        uint256 borrowAmount;
        uint256 collateralAmount;
    }

    function _preBorrowFaucetApprove(FraxlendPair _fraxlendPair, BorrowAction memory _borrowAction) internal {
        IERC20 _collateral = _fraxlendPair.collateralContract();
        faucetFunds(_collateral, _borrowAction.collateralAmount, _borrowAction.user);
        _collateral.approve(address(_fraxlendPair), _borrowAction.collateralAmount);
    }

    // helper to approve and lend in one step
    function borrowToken(
        uint256 _amountToBorrow,
        uint256 _collateralAmount,
        address _user
    ) internal returns (uint256 _finalShares, uint256 _finalCollateralBalance) {
        (_finalShares, _finalCollateralBalance) = borrowToken(pair, _amountToBorrow, _collateralAmount, _user);
    }

    function borrowToken(
        FraxlendPair _pair,
        uint256 _amountToBorrow,
        uint256 _collateralAmount,
        address _user
    ) internal returns (uint256 _finalShares, uint256 _finalCollateralBalance) {
        vm.startPrank(_user);
        collateral.approve(address(pair), _collateralAmount);
        _pair.borrowAsset(uint128(_amountToBorrow), _collateralAmount, _user);
        _finalShares = pair.userBorrowShares(_user);
        _finalCollateralBalance = pair.userCollateralBalance(_user);
        vm.stopPrank();
    }

    function borrowTokenWithFaucet(
        FraxlendPair _fraxlendPair,
        BorrowAction memory _borrowAction
    ) internal returns (uint256 _finalShares, uint256 _finalCollateralBalance) {
        faucetFunds(_fraxlendPair.collateralContract(), _borrowAction.collateralAmount, _borrowAction.user);
        (_finalShares, _finalCollateralBalance) = borrowToken(
            _fraxlendPair,
            _borrowAction.borrowAmount,
            _borrowAction.collateralAmount,
            _borrowAction.user
        );
    }

    // Repaying
    struct RepayAction {
        FraxlendPair fraxlendPair;
        address user;
        uint256 shares;
    }

    function _preRepayFaucetApprove(RepayAction memory _repayAction) internal {
        IERC20 _asset = IERC20(_repayAction.fraxlendPair.asset());
        faucetFunds(_asset, _repayAction.shares * 2, _repayAction.user);
        _asset.approve(address(_repayAction.fraxlendPair), _repayAction.shares);
    }

    // helper to approve and repay in one step, should have called addInterest before hand

    function repayToken(
        FraxlendPair _fraxlendPair,
        uint256 _sharesToRepay,
        address _user
    ) internal returns (uint256 _finalShares) {
        uint256 _amountToApprove = toBorrowAmount(_sharesToRepay, true);
        asset.approve(address(_fraxlendPair), _amountToApprove);
        _fraxlendPair.repayAsset(_sharesToRepay, _user);
        _finalShares = _fraxlendPair.userBorrowShares(_user);
    }

    function repayTokenWithFaucet(
        FraxlendPair _fraxlendPair,
        uint256 _sharesToRepay,
        address _user
    ) internal returns (uint256 _finalShares) {
        faucetFunds(IERC20(_fraxlendPair.asset()), 2 * _sharesToRepay, _user);
        _finalShares = repayToken(_fraxlendPair, _sharesToRepay, _user);
    }

    function repayTokenWithFaucet(RepayAction memory _repayAction) internal returns (uint256 _finalShares) {
        FraxlendPair _fraxlendPair = _repayAction.fraxlendPair;
        faucetFunds(
            IERC20(_fraxlendPair.asset()),
            _fraxlendPair.toBorrowAmount(_repayAction.shares, true, true),
            _repayAction.user
        );
        _finalShares = repayToken(_fraxlendPair, _repayAction.shares, _repayAction.user);
    }

    // helper to move forward multiple blocks and add interest each time
    function addInterestAndMineBulk(uint256 _blocks) internal returns (uint256 _sumOfInt) {
        _sumOfInt = 0;
        for (uint256 i = 0; i < _blocks; i++) {
            mineOneBlock();
            (uint256 _interestEarned,,,) = pair.addInterest(false);

            _sumOfInt += _interestEarned;
        }
    }

    // Withdraw / Redeeming

    // struct WithdrawAction {
    //     FraxlendPair fraxlendPair;
    //     address user;
    //     uint256 amount;
    // }

    // struct RedeemAction {
    //     FraxlendPair fraxlendPair;
    //     address user;
    //     uint256 shares;
    // }

    // function _preRedeemFaucetApprove(RedeemAction memory _redeemAction) internal {
    //     IERC20 _asset = IERC20(_redeemAction.fraxlendPair.asset());
    //     faucetFunds(_asset, _redeemAction.shares * 2, _redeemAction.user);
    //     _asset.approve(address(_redeemAction.fraxlendPair), _redeemAction.shares * 2);
    // }

    // function redeemTokenWithFaucet(RedeemAction memory _redeemAction) internal returns (uint256 _amount) {
    //     startHoax(_redeemAction.user);
    //     faucetFunds(IERC20(_redeemAction.fraxlendPair.asset()), _redeemAction.shares * 2, _redeemAction.user);
    //     _amount = redeemToken(_redeemAction);
    //     vm.stopPrank();
    // }

    // function redeemToken(RedeemAction memory _redeemAction) internal returns (uint256 _amount) {
    //     _amount = _redeemAction.fraxlendPair.redeem(_redeemAction.shares, _redeemAction.user, _redeemAction.user);
    // }
}
