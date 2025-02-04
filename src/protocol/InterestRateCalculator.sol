// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { IRateCalculator } from "../interfaces/IRateCalculator.sol";
import { IERC4626 } from "../interfaces/IERC4626.sol";
import { IStakedFrax } from "../interfaces/IStakedFrax.sol";

/// @title Calculate rates based on the underlying vaults with some floor settings
contract InterestRateCalculator is IRateCalculator {
    using Strings for uint256;

    address public constant sfrax = address(0xA663B02CF0a4b149d2aD41910CB81e23e1c41c32);
    uint256 public constant REWARDS_CYCLE_LENGTH = 604800;

    /// @notice The name suffix for the interest rate calculator
    string public suffix;

    /// @notice the absolute minimum rate
    uint256 public immutable minimumRate;
    uint256 public immutable rateRatio;

    /// @notice The ```constructor``` function
    /// @param _suffix The suffix of the contract name
    constructor(
        string memory _suffix,
        uint256 _minimumRate,
        uint256 _rateRatio
    ) {
        suffix = _suffix;
        minimumRate = _minimumRate;
        rateRatio = _rateRatio;
    }

    /// @notice The ```name``` function returns the name of the rate contract
    /// @return memory name of contract
    function name() external view returns (string memory) {
        return string(abi.encodePacked("InterestRateCalculator ", suffix));
    }

    /// @notice The ```version``` function returns the semantic version of the rate contract
    /// @dev Follows semantic versioning
    /// @return _major Major version
    /// @return _minor Minor version
    /// @return _patch Patch version
    function version() external pure returns (uint256 _major, uint256 _minor, uint256 _patch) {
        _major = 1;
        _minor = 0;
        _patch = 0;
    }

    function sfraxRates() public view returns(uint256 fraxPerSecond){
        //on fraxtal need to get pricefeed, on mainnet check directly on sfrax
        // address pricefeed = IStakedFrax(sfrax).priceFeedVault();

        IStakedFrax.RewardsCycleData memory rdata = IStakedFrax(sfrax).rewardsCycleData();
        uint256 sfraxtotal = IStakedFrax(sfrax).storedTotalAssets();
        if(sfraxtotal == 0){
            sfraxtotal = 1;
        }
        uint256 maxsfraxDistro = IStakedFrax(sfrax).maxDistributionPerSecondPerAsset();
        fraxPerSecond = rdata.rewardCycleAmount / (rdata.cycleEnd - rdata.lastSync);
        fraxPerSecond = fraxPerSecond * 1e18 / sfraxtotal;
        fraxPerSecond = fraxPerSecond > maxsfraxDistro ? maxsfraxDistro : fraxPerSecond;
    }

    /// @notice The ```getNewRate``` function calculates interest rates using underlying rates and minimums
    /// @param _deltaTime The elapsed time since last update, given in seconds
    /// @return _newRatePerSec The new interest rate, 18 decimals of precision
    function getNewRate(
        address _vault,
        uint256 _deltaTime,
        uint256 _previousShares
    ) external view returns (uint64 _newRatePerSec, uint128 _newShares) {
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
        //take ratio of the difference
        difference /= rateRatio;

        //take ratio of sfrax rate and compare to our hard minimum, take higher as our minimum
        //this lets us base our minimum rates on a "risk free rate" product
        uint256 floorRate = sfraxRates() / rateRatio;
        floorRate = floorRate > minimumRate ? floorRate : minimumRate;

        //if difference is over some minimum, return difference
        //if not, return minimum
        _newRatePerSec = difference > floorRate ? uint64(difference) : uint64(floorRate);
    }
}
