// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "src/libraries/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "frax-std/Logger.sol";
import "src/protocol/fraxlend/FraxlendPair.sol";
import "src/interfaces/IVariableInterestRateV2.sol";
import "src/interfaces/oracles/abstracts/IEthUsdChainlinkOracleWithMaxDelay.sol";
import "src/interfaces/oracles/abstracts/IUniswapV3SingleTwapOracle.sol";
import "./General.sol";
import "./FraxlendPairTestHelper.sol";

library FraxlendPairConfigurationHelper {
    using FraxlendPairTestHelper for FraxlendPair;
    using RateHelper for IVariableInterestRateV2;
    using Strings for uint256;
    using NumberFormat for *;
    using SafeERC20 for IERC20;

    // ============================================================================================
    // Post Deployment Helpers
    // ============================================================================================
    function displayConstructorParams(FraxlendPair _fraxlendPair) public view {
        console.log("");
        console.log("======================================================================================");
        console.log("The following are the constructor params");
        console.log("======================================================================================");
        console.log("asset: ", IERC20(_fraxlendPair.asset()).safeName());
        console.log("collateral: ", string(IERC20(address(_fraxlendPair.collateralContract())).safeName()));
        console.log("oracle: ", IERC20(_fraxlendPair.__getOracle()).safeName());

        Logger.percent(
            "maxOracleDeviation: ",
            _fraxlendPair.__getMaxOracleDeviation(),
            _fraxlendPair.DEVIATION_PRECISION()
        );
        console.log("rateContract: ", IERC20(address(_fraxlendPair.rateContract())).safeName());
        Logger.rate("fullUtilizationRate: ", _fraxlendPair.__getFullUtilizationRate());
        Logger.percent("maxLTV: ", _fraxlendPair.maxLTV(), _fraxlendPair.LTV_PRECISION());
        Logger.percent("LiquidationFee: ", _fraxlendPair.liquidationFee(), _fraxlendPair.FEE_PRECISION());
        // Logger.percent(
        //     "protocolLiquidationFee: ",
        //     _fraxlendPair.protocolLiquidationFee(),
        //     _fraxlendPair.FEE_PRECISION()
        // );
    }

    // function displayMetadata(FraxlendPair _fraxlendPair) public {
    //     {
    //         console.log("");
    //         console.log("======================================================================================");
    //         console.log("The following are metadata parameters of the contract");
    //         console.log("======================================================================================");
    //         string memory _name = _fraxlendPair.name();
    //         console.log("fraxlendPair.name():", _name);
    //         uint256 _decimals = _fraxlendPair.decimals();
    //         console.log("fraxlendPair.decimals():", _decimals);
    //         string memory _symbol = _fraxlendPair.symbol();
    //         console.log("fraxlendPair.symbol():", _symbol);
    //         require(
    //             _decimals == IERC20(_fraxlendPair.asset()).safeDecimals(),
    //             "Asset decimals must be equal to FraxlendPair decimals"
    //         );
    //         console.log("Contract decimals passed tests");
    //     }
    // }

    function displayRateContract(FraxlendPair _fraxlendPair) public view {
        {
            console.log("");
            console.log("======================================================================================");
            console.log("The following are parameters and information for the currently configured Rate Contract");
            console.log("======================================================================================");
            IVariableInterestRateV2 _rateContract = IVariableInterestRateV2(address(_fraxlendPair.rateContract()));
            RateHelper.RateCalculatorParams memory _rateCalculatorParams = _rateContract.__getRateCalculatorParams();
            console.log("Utilization Parameters of the rate contract");
            Logger.percent(
                "The value below which the full utilization rate will decline, MIN_TARGET_UTIL:",
                _rateCalculatorParams.MIN_TARGET_UTIL,
                _rateCalculatorParams.UTIL_PREC
            );
            Logger.percent(
                "The utilization above which the full utilization rate will increase, MAX_TARGET_UTIL:",
                _rateCalculatorParams.MAX_TARGET_UTIL,
                _rateCalculatorParams.UTIL_PREC
            );

            Logger.percent(
                "The utilization at which the two lines meet, VERTEX_UTILIZATION:",
                _rateCalculatorParams.VERTEX_UTILIZATION,
                _rateCalculatorParams.UTIL_PREC
            );
            console.log("_rateCalculatorParams.UTIL_PREC", _rateCalculatorParams.UTIL_PREC);

            console.log("");
            console.log("Rate Parameters of the rate contract");
            Logger.rate("The rate when utilization is 0%,  ZERO_UTIL_RATE:", _rateCalculatorParams.ZERO_UTIL_RATE);

            Logger.percent(
                "The percentage of the delta between Zero and Full utilization rates, which is used to calculate the vertex rate VERTEX_RATE_PERCENT",
                _rateCalculatorParams.VERTEX_RATE_PERCENT,
                1e18
            );

            Logger.rate(
                "The minimum the rate can be when utilization is 100%, MIN_FULL_UTIL_RATE:",
                _rateCalculatorParams.MIN_FULL_UTIL_RATE
            );

            Logger.rate(
                "The maximum the rate can be when utilization is 100%, MAX_FULL_UTIL_RATE",
                _rateCalculatorParams.MAX_FULL_UTIL_RATE
            );
            console.log("The precision of all rate values, RATE_PREC", _rateCalculatorParams.RATE_PREC);
            console.log(
                string(
                    abi.encodePacked(
                        "The rate half life, the time it takes to half/double the 100% rate, RATE_HALF_LIFE (seconds): ",
                        uint256(_rateCalculatorParams.RATE_HALF_LIFE).toString()
                    )
                )
            );
            console.log(
                string(
                    abi.encodePacked(
                        "The rate half life, the time it takes to half/double the 100% rate, RATE_HALF_LIFE (hours): ",
                        ((1e18 * uint256(_rateCalculatorParams.RATE_HALF_LIFE)) / 3600).toDecimal(1e18)
                    )
                )
            );

            (
                uint32 _lastBlock,
                uint32 _feeToProtocolRate, // Fee amount 1e5 precision
                uint64 _lastTimestamp,
                uint64 _ratePerSec,
                uint64 _fullUtilizationRate
            ) = _fraxlendPair.currentRateInfo();
            console.log("");
            console.log("_currentRateInfo.lastBlock", _lastBlock);
            console.log("_currentRateInfo.feeToProtocolRate", _feeToProtocolRate);
            console.log("_currentRateInfo.lastTimestamp", _lastTimestamp);
            Logger.rate("_currentRateInfo.ratePerSec", uint256(_ratePerSec));
            Logger.rate("_currentRateInfo.fullUtilizationRate", _fullUtilizationRate);

            console.log("");
            console.log("Currently the interest rate curve has the following values");
            (uint256 _zeroRatePerSec, ) = _rateContract.getNewRate(12, 0, _fullUtilizationRate);
            Logger.rate("0% Utilization rate:", _zeroRatePerSec);
            (uint256 _vertexRatePerSec, ) = _rateContract.getNewRate(
                0,
                _rateCalculatorParams.VERTEX_UTILIZATION,
                _fullUtilizationRate
            );
            Logger.rate("vertex utilization rate:", _vertexRatePerSec);
            (uint256 _fullRatePerSec, ) = _rateContract.getNewRate(
                0,
                _rateCalculatorParams.UTIL_PREC,
                _fullUtilizationRate
            );
            Logger.rate("100% Utilization rate:", _fullRatePerSec);
        }
    }

    function displayExchangeRateData(FraxlendPair _fraxlendPair) public view {
        {
            console.log("");
            console.log("======================================================================================");
            console.log("The following are exchange rate parameters of the contract");
            console.log("======================================================================================");

            uint256 _lowExchangeRate = _fraxlendPair.__getLowExchangeRate();
            uint256 _highExchangeRate = _fraxlendPair.__getHighExchangeRate();

            console.log("ExchangeRate is given in Collateral / Asset, i.e. How much collateral to buy 1e18 Asset");
            console.log("1 Asset Token is worth how much Collateral Token");
            uint256 EXCHANGE_PRECISION = _fraxlendPair.EXCHANGE_PRECISION();
            console.log("EXCHANGE_PRECISION", EXCHANGE_PRECISION);
            Logger.decimal("(Low)Collateral per Asset", _lowExchangeRate, EXCHANGE_PRECISION);
            Logger.decimal("(Low) Asset per Collateral", 1e36 / _lowExchangeRate, EXCHANGE_PRECISION);
            Logger.decimal("(High)Collateral per Asset", _highExchangeRate, EXCHANGE_PRECISION);
            Logger.decimal("(High) Asset per Collateral", 1e36 / _highExchangeRate, EXCHANGE_PRECISION);

            uint256 DEVIATION_PRECISION = _fraxlendPair.DEVIATION_PRECISION();
            console.log("DEVIATION_PRECISION", DEVIATION_PRECISION);
            uint256 _deviation = (DEVIATION_PRECISION * (_highExchangeRate - _lowExchangeRate)) / _highExchangeRate;
            Logger.percent("current deviation", _deviation, DEVIATION_PRECISION);
            uint256 _maxOracleDeviation = _fraxlendPair.__getMaxOracleDeviation();
            Logger.percent("_maxOracleDeviation is set to: ", _maxOracleDeviation, DEVIATION_PRECISION);
        }
    }

    function displayCustomDeployData(FraxlendPair _fraxlendPair) public view {
        {
            console.log("");
            console.log("======================================================================================");
            console.log("The following are the custom deployment configurations of the contract");
            console.log("======================================================================================");
            uint256 _maxLTV = _fraxlendPair.maxLTV();
            uint256 _LTV_PRECISION = _fraxlendPair.LTV_PRECISION();
            console.log("_LTV_PRECISION", _LTV_PRECISION);
            Logger.percent("_maxLTV", _maxLTV, _LTV_PRECISION);

            uint256 _LIQ_PRECISION = _fraxlendPair.LIQ_PRECISION();
            console.log("_LIQ_PRECISION", _LIQ_PRECISION);
            uint256 _liquidationFee = _fraxlendPair.liquidationFee();
            // uint256 _dirtyLiquidationFee = _fraxlendPair.dirtyLiquidationFee();
            // uint256 _protocolLiquidationFee = _fraxlendPair.protocolLiquidationFee();
            Logger.percent("_liquidationFee", _liquidationFee, _LIQ_PRECISION);
            // Logger.percent("_dirtyLiquidationFee", _dirtyLiquidationFee, _LIQ_PRECISION);
            // Logger.percent("_protocolLiquidationFee", _protocolLiquidationFee, _LIQ_PRECISION);

            // Ensure maxLTV*liquidationFee < 100%
            require(
                ((_maxLTV * (_liquidationFee)) / _LIQ_PRECISION) < _LTV_PRECISION,
                "Ensure maxLTV*liquidationFee < 100%"
            );
            // require(_dirtyLiquidationFee < _cleanLiquidationFee, "Ensure dirtyLiquidationFee < cleanLiquidationFee");
            // require(
            //     _protocolLiquidationFee < _dirtyLiquidationFee,
            //     "Ensure protocolLiquidationFee < dirtyLiquidationFee"
            // );
            console.log("maxLTV, liquidationFee configured properly and passed tests");

            // console.log("");
            // console.log("customConfigData:");
            // console.logBytes(abi.encode(_fraxlendPair.name(), _fraxlendPair.symbol(), _fraxlendPair.decimals()));
        }
    }

    function displayOracleInfo(FraxlendPair _fraxlendPair) public view {
        console.log("");
        console.log("======================================================================================");
        console.log("The following is information about the oracle");
        console.log("======================================================================================");

        address _oracleAddress = _fraxlendPair.__getOracle();
        string memory _oracleName = IDualOracle(_oracleAddress).name();
        console.log("_oracleName", _oracleName);
        uint8 _oracleDecimals = IDualOracle(_oracleAddress).decimals();
        console.log("_oracleDecimals", _oracleDecimals);
        IDualOracle _oracle = IDualOracle(_oracleAddress);
        (, uint256 _lowPrice, uint256 _highPrice) = IDualOracle(_oracleAddress).getPrices();
        uint256 _precision = IDualOracle(_oracleAddress).ORACLE_PRECISION();

        Logger.decimal("_lowPrice (asset per collateral)", _lowPrice, _precision);
        Logger.decimal("_lowPrice (collateral per asset)", _precision ** 2 / _lowPrice, _precision);
        Logger.decimal("_highPrice (asset per collateral)", _highPrice, _precision);
        Logger.decimal("_highPrice (collateral per asset)", _precision ** 2 / _highPrice, _precision);
        if (_oracle.supportsInterface(type(IEthUsdChainlinkOracleWithMaxDelay).interfaceId)) {
            displayEthUsdChainlinkOracleInfo(_oracleAddress);
        }
        if (_oracle.supportsInterface(type(IUniswapV3SingleTwapOracle).interfaceId)) {
            displayUniswapV3SingleTwapOracleInfo(_oracleAddress);
        }
    }

    function displayEthUsdChainlinkOracleInfo(address _oracleAddress) public view {
        IEthUsdChainlinkOracleWithMaxDelay _oracle = IEthUsdChainlinkOracleWithMaxDelay(_oracleAddress);
        console.log("");
        console.log("======================================================================================");
        console.log("The following is information about the Eth Usd Chainlink Oracle");
        console.log("======================================================================================");
        address _ETH_USD_CHAINLINK_FEED_ADDRESS = _oracle.ETH_USD_CHAINLINK_FEED_ADDRESS();
        console.log("ETH_USD_CHAINLINK_FEED_ADDRESS: ", _ETH_USD_CHAINLINK_FEED_ADDRESS);
        uint8 _ETH_USD_CHAINLINK_FEED_DECIMALS = _oracle.ETH_USD_CHAINLINK_FEED_DECIMALS();
        console.log("ETH_USD_CHAINLINK_FEED_DECIMALS: ", _ETH_USD_CHAINLINK_FEED_DECIMALS);
        uint256 _ETH_USD_CHAINLINK_FEED_PRECISION = _oracle.ETH_USD_CHAINLINK_FEED_PRECISION();
        console.log(" maximumEthUsdOracleDelay (seconds): ", _oracle.maximumEthUsdOracleDelay());
        Logger.decimal(" maximumEthUsdOracleDelay (minutes): ", (1e5 * _oracle.maximumEthUsdOracleDelay()) / 60, 1e5);
        Logger.scientific("ETH_USD_CHAINLINK_FEED_PRECISION: ", _ETH_USD_CHAINLINK_FEED_PRECISION);
        (, , uint256 _ethUsdPrice) = _oracle.getEthUsdChainlinkPrice();
        // The current price in both directions
        Logger.decimal(
            "The current price USD per ETH from getEthUsdChainlinkPrice()",
            _ethUsdPrice,
            _ETH_USD_CHAINLINK_FEED_PRECISION
        );
        Logger.decimal(
            "The current price ETH per USD from getEthUsdChainlinkPrice()",
            (_ETH_USD_CHAINLINK_FEED_PRECISION * _ETH_USD_CHAINLINK_FEED_PRECISION) / _ethUsdPrice,
            _ETH_USD_CHAINLINK_FEED_PRECISION
        );
        // The return value for public functions
        // The current config values
    }

    function displayUniswapV3SingleTwapOracleInfo(address _oracleAddress) public view {
        IUniswapV3SingleTwapOracle _oracle = IUniswapV3SingleTwapOracle(_oracleAddress);
        console.log("");
        console.log("======================================================================================");
        console.log("The following is information about the UniswapV3SingleTwapOracle");
        console.log("======================================================================================");
        // Add more stuff here
        uint256 _twapDuration = _oracle.twapDuration();
        console.log("_twapDuration (seconds)", _twapDuration);
        console.log("_twapDuration (minutes)", ((1e5 * _twapDuration) / 60).toDecimal(1e5));
    }

    function displayAssetCollateralInfo(FraxlendPair _fraxlendPair) public view {
        console.log("");
        console.log("======================================================================================");
        console.log("The following is information about the asset and collateral contracts");
        console.log("======================================================================================");
        IERC20 _collateralContract = IERC20(address(_fraxlendPair.collateralContract()));
        string memory _collateralName = _collateralContract.safeName();
        console.log("_collateralName", _collateralName);
        uint8 _collateralDecimals = _collateralContract.safeDecimals();
        console.log("_collateralDecimals", _collateralDecimals);

        IERC20 _assetContract = IERC20(_fraxlendPair.asset());
        string memory _assetName = _assetContract.safeName();
        console.log("_assetName", _assetName);
        uint8 _assetDecimals = _assetContract.safeDecimals();
        console.log("_assetDecimals", _assetDecimals);
    }

    function __displayPostDeploymentData(FraxlendPair _fraxlendPair) public {
        displayConstructorParams(_fraxlendPair);
        // displayMetadata(_fraxlendPair);
        displayAssetCollateralInfo(_fraxlendPair);
        displayExchangeRateData(_fraxlendPair);
        displayOracleInfo(_fraxlendPair);
        displayRateContract(_fraxlendPair);
        displayCustomDeployData(_fraxlendPair);
    }

    function __displayPostDeploymentDataFxb(FraxlendPair _fraxlendPair) public {
        displayConstructorParams(_fraxlendPair);
        // displayMetadata(_fraxlendPair);
        displayAssetCollateralInfo(_fraxlendPair);
        displayExchangeRateData(_fraxlendPair);
        /// @dev Non-standard Oracles for FXB pairs
        // displayOracleInfo(_fraxlendPair);
        displayRateContract(_fraxlendPair);
        displayCustomDeployData(_fraxlendPair);
    }
}
