// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "src/protocol/fraxlend/FraxlendPair.sol";

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
        uint256 claimableFees;
        FraxlendPair.CurrentRateInfo currentRateInfo;
        VaultAccount totalBorrow;
    }

    function __addInterest(FraxlendPair _pair) internal returns (InterestResults memory _results) {
        (
            uint256 _interestEarned,
            FraxlendPair.CurrentRateInfo memory _currentRateInfo,
            uint256 _claimableFees,
            VaultAccount memory _totalBorrow
        ) = _pair.addInterest(true);
        _results.interestEarned = _interestEarned;
        _results.currentRateInfo = _currentRateInfo;
        _results.claimableFees = _claimableFees;
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
        // (, , VaultAccount memory _totalAsset, VaultAccount memory _totalBorrow) = _pair.previewAddInterest();
        // return _totalAsset.amount - _totalBorrow.amount;
        return _pair.totalAssetAvailable();
    }

    function __totalBorrowAmount(FraxlendPair _pair) internal view returns (uint256 _totalBorrowAmount) {
        (, , , VaultAccount memory _totalBorrow) = _pair.previewAddInterest();
        return _totalBorrow.amount;
    }

    function __totalClaimableFees(FraxlendPair _pair) internal view returns (uint256 _claimableFees) {
        (, , _claimableFees, ) = _pair.previewAddInterest();
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
    ) external view returns (uint256 _userBorrowShares, uint256 _userCollateralBalance) {
        _userBorrowShares = _fraxlendPair.userBorrowShares(_address);
        _userCollateralBalance = _fraxlendPair.userCollateralBalance(_address);
    }

    function __getPairAccounting(
        FraxlendPair _fraxlendPair
    )
        external
        view
        returns (
            uint256 _claimableFees,
            uint128 _totalBorrowAmount,
            uint128 _totalBorrowShares,
            uint256 _totalCollateral
        )
    {
        _claimableFees = _fraxlendPair.claimableFees();
        (_totalBorrowAmount, _totalBorrowShares) = _fraxlendPair.totalBorrow();
        _totalCollateral = _fraxlendPair.totalCollateral();
    }
}
