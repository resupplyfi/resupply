pragma solidity 0.8.28;

interface IInterestRateCalculatorV2 {
    function getNewRate(
        address _vault,
        uint256 _deltaTime,
        uint256 _previousShares
    ) external view returns (uint64 _newRatePerSec, uint128 _newShares);

    function getPairRateWithUnderlying(
        address _pair,
        uint256 _underlyingRate
    ) external view returns (uint256 _newRatePerSec);

    function minimumRate() external view returns (uint256);

    function name() external view returns (string memory);

    function rateRatio() external view returns (uint256);

    function sfrxusd() external view returns (address);

    function sfrxusdRates() external view returns (uint256 fraxPerSecond);

    function suffix() external view returns (string memory);

    function rateRatioBase() external view returns (uint256);
    function rateRatioBaseCollateral() external view returns (uint256);
    function rateRatioAdditional() external view returns (uint256);

    function version()
        external
        pure
        returns (
            uint256 _major,
            uint256 _minor,
            uint256 _patch
        );
}