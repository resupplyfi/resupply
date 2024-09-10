// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "src/FraxlendPair.sol";

library FraxlendPairTestHelper {
    function __getCurrentRate(FraxlendPair _pair) internal view returns (uint256 _currentRate) {
        (, , , _currentRate, ) = _pair.currentRateInfo();
    }

    function __getFullUtilizationRate(FraxlendPair _pair) internal view returns (uint256 _fullUtilizationRate) {
        (, , , , _fullUtilizationRate) = _pair.currentRateInfo();
    }

    function __getLastInterestTimestamp(FraxlendPair _pair) internal view returns (uint256 _lastInterestUpdate) {
        (, , _lastInterestUpdate, , ) = _pair.currentRateInfo();
    }

    struct InterestResults {
        uint256 interestEarned;
        uint256 feesAmount;
        uint256 feesShare;
        FraxlendPair.CurrentRateInfo currentRateInfo;
        VaultAccount totalAsset;
        VaultAccount totalBorrow;
    }

    function __addInterest(FraxlendPair _pair) internal returns (InterestResults memory _results) {
        (
            uint256 _interestEarned,
            uint256 _feesAmount,
            uint256 _feesShare,
            FraxlendPair.CurrentRateInfo memory _currentRateInfo,
            VaultAccount memory _totalAsset,
            VaultAccount memory _totalBorrow
        ) = _pair.addInterest(true);
        _results.interestEarned = _interestEarned;
        _results.feesAmount = _feesAmount;
        _results.feesShare = _feesShare;
        _results.currentRateInfo = _currentRateInfo;
        _results.totalAsset = _totalAsset;
        _results.totalBorrow = _totalBorrow;
    }

    function __addInterestGetEarned(FraxlendPair _pair) internal returns (uint256 _interestEarned) {
        InterestResults memory _results = __addInterest(_pair);
        _interestEarned = _results.interestEarned;
    }

    function __addInterestGetRate(FraxlendPair _pair) internal returns (uint256 _newRate) {
        InterestResults memory _results = __addInterest(_pair);
        _newRate = _results.currentRateInfo.ratePerSec;
    }

    function __totalAssetsAvailable(FraxlendPair _pair) internal view returns (uint256 _totalAssetsAvailable) {
        (, , , , VaultAccount memory _totalAsset, VaultAccount memory _totalBorrow) = _pair.previewAddInterest();
        return _totalAsset.amount - _totalBorrow.amount;
    }

    function __totalBorrowAmount(FraxlendPair _pair) internal view returns (uint256 _totalBorrowAmount) {
        (, , , , , VaultAccount memory _totalBorrow) = _pair.previewAddInterest();
        return _totalBorrow.amount;
    }

    function __totalAssetAmount(FraxlendPair _pair) internal view returns (uint256 _totalAssetAmount) {
        (, , , , VaultAccount memory _totalAsset, ) = _pair.previewAddInterest();
        return _totalAsset.amount;
    }

    function __updateExchangeRateGetLow(FraxlendPair _pair) internal returns (uint256 _low) {
        (, uint256 _newLow, uint256 _newHigh) = _pair.updateExchangeRate();
        _low = _newLow;
    }

    function __updateExchangeRateGetHigh(FraxlendPair _pair) internal returns (uint256 _high) {
        (, uint256 _newLow, uint256 _newHigh) = _pair.updateExchangeRate();
        _high = _newHigh;
    }

    function __getLowExchangeRate(FraxlendPair _pair) internal view returns (uint256 _low) {
        (, , , _low, ) = _pair.exchangeRateInfo();
    }

    function __getHighExchangeRate(FraxlendPair _pair) internal view returns (uint256 _high) {
        (, , , , _high) = _pair.exchangeRateInfo();
    }

    function __getMaxOracleDeviation(FraxlendPair _pair) internal view returns (uint32 _maxOracleDeviation) {
        (, _maxOracleDeviation, , , ) = _pair.exchangeRateInfo();
    }

    function __getOracle(FraxlendPair _pair) internal view returns (address _oracle) {
        (_oracle, , , , ) = _pair.exchangeRateInfo();
    }

    function __getUserSnapshot(
        FraxlendPair _fraxlendPair,
        address _address
    ) external view returns (uint256 _userAssetShares, uint256 _userBorrowShares, uint256 _userCollateralBalance) {
        _userAssetShares = _fraxlendPair.balanceOf(_address);
        _userBorrowShares = _fraxlendPair.userBorrowShares(_address);
        _userCollateralBalance = _fraxlendPair.userCollateralBalance(_address);
    }

    function __getPairAccounting(
        FraxlendPair _fraxlendPair
    )
        external
        view
        returns (
            uint128 _totalAssetAmount,
            uint128 _totalAssetShares,
            uint128 _totalBorrowAmount,
            uint128 _totalBorrowShares,
            uint256 _totalCollateral
        )
    {
        (_totalAssetAmount, _totalAssetShares) = _fraxlendPair.totalAsset();
        (_totalBorrowAmount, _totalBorrowShares) = _fraxlendPair.totalBorrow();
        _totalCollateral = _fraxlendPair.totalCollateral();
    }
}
