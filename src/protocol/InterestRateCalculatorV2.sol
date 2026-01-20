// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { CoreOwnable } from '../dependencies/CoreOwnable.sol';
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { IRateCalculator } from "../interfaces/IRateCalculator.sol";
import { IERC4626 } from "../interfaces/IERC4626.sol";
import { IStakedFrax } from "../interfaces/frax/IStakedFrax.sol";
import { IPriceWatcher } from "../interfaces/IPriceWatcher.sol";
import { IResupplyPair } from "../interfaces/IResupplyPair.sol";

/// @title Calculate rates based on the underlying vaults with some floor settings
contract InterestRateCalculatorV2 is IRateCalculator, CoreOwnable {
    using Strings for uint256;

    uint256 internal constant _MAJOR = 2;
    uint256 internal constant _MINOR = 1;
    uint256 internal constant _PATCH = 0;

    address public constant sfrxusd = address(0xcf62F905562626CfcDD2261162a51fd02Fc9c5b6);

    address public immutable priceWatcher;
    /// @notice the absolute minimum borrow rate per second (1e18 scaled)
    uint256 public immutable minimumRate;
    /// @notice off-peg amplifier expressed as a percentage of the selected base multiplier.
    /// @dev 1e18 = +100% of base when priceweight == 1e6.
    uint256 public immutable rateRatioAdditional;
    /// @notice multiplier applied when risk-free rate is selected (1e18 = 1x)
    uint256 public rateRatioBase;
    /// @notice multiplier applied when collateral rate is selected (1e18 = 1x)
    uint256 public rateRatioBaseCollateral;

    event SetRateInfo(uint256 _rateRatioBase, uint256 _rateRatioBaseCollateral);

    /// @notice The ```constructor``` function
    /// @param _minimumRate Floor rate applied during rate calculation
    /// @param _rateRatioBase ratio base of both the underlying APR and sFRXUSD rate
    /// @param _rateRatioAdditional additional max ratio added to base
    /// @param _priceWatcher price watcher contract
    constructor(
        address _core,
        uint256 _minimumRate,
        uint256 _rateRatioBase,
        uint256 _rateRatioBaseCollateral,
        uint256 _rateRatioAdditional,
        address _priceWatcher
    ) CoreOwnable(_core){
        minimumRate = _minimumRate;
        rateRatioBase = _rateRatioBase;
        rateRatioBaseCollateral = _rateRatioBaseCollateral;
        rateRatioAdditional = _rateRatioAdditional;
        priceWatcher = _priceWatcher;
        require(priceWatcher != address(0), "PriceWatcher must be set");
        emit SetRateInfo(_rateRatioBase, _rateRatioBaseCollateral);
    }

    function name() external pure returns (string memory) {
        return string(
            abi.encodePacked(
                "InterestRateCalculator v",
                Strings.toString(_MAJOR), ".",
                Strings.toString(_MINOR), ".",
                Strings.toString(_PATCH)
            )
        );
    }

    /// @notice Updates the base multipliers used to derive the per-second borrow rate.
    /// @param _rateRatioBase 1e18 scaled multiplier applied when risk-free rate is selected.
    /// @param _rateRatioBaseCollateral 1e18 scaled multiplier applied when collateral rate is selected.
    function setRateInfo(uint256 _rateRatioBase, uint256 _rateRatioBaseCollateral) external onlyOwner{

        uint256 _additionalBaseRate = _rateRatioBase * rateRatioAdditional / 1e18;
        uint256 _additionalBaseCollateralRate = _rateRatioBaseCollateral * rateRatioAdditional / 1e18;

        //if additional changes to % then this needs to be updated
        require(_rateRatioBase + _additionalBaseRate < 1e18, "total rate must be below 100%");
        require(_rateRatioBaseCollateral + _additionalBaseCollateralRate < 1e18, "total collateral rate must be below 100%");

        rateRatioBase = _rateRatioBase;
        rateRatioBaseCollateral = _rateRatioBaseCollateral;
        emit SetRateInfo(_rateRatioBase, _rateRatioBaseCollateral);
    }

    /// @notice The ```version``` function returns the semantic version of the rate contract
    /// @dev Follows semantic versioning
    /// @return _major Major version
    /// @return _minor Minor version
    /// @return _patch Patch version
    function version() external pure returns (uint256 _major, uint256 _minor, uint256 _patch) {
        return (_MAJOR, _MINOR, _PATCH);
    }

    function sfrxusdRates() public view returns(uint256 fraxPerSecond){
        //on fraxtal need to get pricefeed, on mainnet check directly on sfrxusd
        IStakedFrax.RewardsCycleData memory rdata = IStakedFrax(sfrxusd).rewardsCycleData();
        uint256 sfrxusdtotal = IStakedFrax(sfrxusd).storedTotalAssets();
        if(sfrxusdtotal == 0){
            sfrxusdtotal = 1;
        }
        uint256 maxsfrxusdDistro = IStakedFrax(sfrxusd).maxDistributionPerSecondPerAsset();
        fraxPerSecond = rdata.rewardCycleAmount / (rdata.cycleEnd - rdata.lastSync);
        fraxPerSecond = fraxPerSecond * 1e18 / sfrxusdtotal;
        fraxPerSecond = fraxPerSecond > maxsfrxusdDistro ? maxsfrxusdDistro : fraxPerSecond;
    }

    /// @notice The ```getNewRate``` function calculates interest rates using underlying rates and minimums
    /// @param _vault The vault to calculate the rate for
    /// @param _deltaTime The elapsed time since last update, given in seconds
    /// @param _previousShares The number of shares at the previous timestamp, 18 decimals of precision
    /// @return _newRatePerSec The new interest rate, 18 decimals of precision
    /// @return _newShares The new number of shares, 18 decimals of precision
    function getNewRate(
        address _vault,
        uint256 _deltaTime,
        uint256 _previousShares
    ) external view returns (uint64 _newRatePerSec, uint128 _newShares) {
        return _getNewRate(msg.sender, _vault, _deltaTime, _previousShares);
    }

    /// @notice The ```getPairRate``` function calculates interest rates using underlying rates and minimums
    /// @dev return values are simplified compared to getNewRate
    /// @param _pair The Resupply pair address to check
    /// @return _newRatePerSec The new interest rate, 18 decimals of precision
    function getPairRate(
        address _pair
    ) external view returns (uint256 _newRatePerSec) {
        (uint64 lastTimestamp, , uint128 lastShares) = IResupplyPair(_pair).currentRateInfo();
        address collateral = IResupplyPair(_pair).collateral();
        uint256 deltaTime = block.timestamp - lastTimestamp;

        //ensure deltatime is not 0
        if(deltaTime == 0){
            deltaTime = 1;
        }

        (_newRatePerSec, ) = _getNewRate(_pair, collateral, deltaTime, lastShares);
    }

    function _getNewRate(
        address _pair,
        address _vault,
        uint256 _deltaTime,
        uint256 _previousShares
    ) internal view returns (uint64 _newRatePerSec, uint128 _newShares) {
        //update how many shares 1e18 of assets are
        _newShares = uint128(IERC4626(_vault).convertToShares(1e18));
        //get new price of previous shares
        uint256 _newPrice = IERC4626(_vault).convertToAssets(_previousShares);

        //get difference of same share count to see asset growth
        uint256 difference = _newPrice > 1e18 ? _newPrice - 1e18 : 0;

        //difference over time (note: delta time is guaranteed to be non-zero)
        //since old price and new price are calculated from the same amount of shares
        //that was equivalent to 1e18 assets at previous timestamp, this becomes our proper rate for 1e18 borrowed
        difference /= _deltaTime;

        //take ratio of sfrxusd rate and compare to our hard minimum, take higher as our minimum
        //this lets us base our minimum rates on a "risk free rate" product
        uint256 riskFreeRate = sfrxusdRates();
        _newRatePerSec = uint64(riskFreeRate > minimumRate ? riskFreeRate : minimumRate);
        uint256 _rateBase;

        // compare collateral rate to max(risk_free_rate, minimum_rate) and set _rateBase accordingly
        if(difference >= _newRatePerSec){
            _newRatePerSec = uint64(difference);
            _rateBase = rateRatioBaseCollateral;
        }
        else {
            _rateBase = rateRatioBase;
        }

        //rateRatioAdditional is a % of base so we need to convert to see how much we add on
        //note: in previous version this was just directly added to rateBase
        uint256 _additionalRate = _rateBase * rateRatioAdditional / 1e18;

        //calculte and apply `rateRatio` multiplier which is computed using the following:
        // 1. priceWeight: which represents the off-peg boost
        // 2. _rateBase: used to achieve the a portion of the rate indicators like sfrxusd and underlying rates
        // 3. _additionalRate: amplifier for off-peg boost
        uint256 priceweight = IPriceWatcher(priceWatcher).findPairPriceWeight(_pair);
        uint256 rateRatio = _rateBase + (_additionalRate * priceweight / 1e6);
        _newRatePerSec = uint64(_newRatePerSec * rateRatio / 1e18);
    }
}