// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "src/protocol/ResupplyPair.sol";

library ResupplyPairTestHelper {
    function __getCurrentRate(ResupplyPair _pair) internal view returns (uint256 _currentRate) {
        (, , , _currentRate, ) = _pair.currentRateInfo();
    }

    function __getFullUtilizationRate(ResupplyPair _pair) internal view returns (uint256 _fullUtilizationRate) {
        (, , , , _fullUtilizationRate) = _pair.currentRateInfo();
    }

    function __getLastInterestTimestamp(ResupplyPair _pair) internal view returns (uint256 _lastInterestUpdate) {
        (, , _lastInterestUpdate, , ) = _pair.currentRateInfo();
    }

    struct InterestResults {
        uint256 interestEarned;
        uint256 feesAmount;
        uint256 feesShare;
        uint256 claimableFees;
        ResupplyPair.CurrentRateInfo currentRateInfo;
        VaultAccount totalBorrow;
    }

    function __addInterest(ResupplyPair _pair) internal returns (InterestResults memory _results) {
        (
            uint256 _interestEarned,
            ResupplyPair.CurrentRateInfo memory _currentRateInfo,
            uint256 _claimableFees,
            VaultAccount memory _totalBorrow
        ) = _pair.addInterest(true);
        _results.interestEarned = _interestEarned;
        _results.currentRateInfo = _currentRateInfo;
        _results.claimableFees = _claimableFees;
        _results.totalBorrow = _totalBorrow;
    }

    function __addInterestGetEarned(ResupplyPair _pair) internal returns (uint256 _interestEarned) {
        InterestResults memory _results = __addInterest(_pair);
        _interestEarned = _results.interestEarned;
    }

    function __addInterestGetRate(ResupplyPair _pair) internal returns (uint256 _newRate) {
        InterestResults memory _results = __addInterest(_pair);
        _newRate = _results.currentRateInfo.ratePerSec;
    }

    function __totalAssetsAvailable(ResupplyPair _pair) internal view returns (uint256 _totalAssetsAvailable) {
        // (, , VaultAccount memory _totalAsset, VaultAccount memory _totalBorrow) = _pair.previewAddInterest();
        // return _totalAsset.amount - _totalBorrow.amount;
        return _pair.totalAssetAvailable();
    }

    function __totalBorrowAmount(ResupplyPair _pair) internal view returns (uint256 _totalBorrowAmount) {
        (, , , VaultAccount memory _totalBorrow) = _pair.previewAddInterest();
        return _totalBorrow.amount;
    }

    function __totalClaimableFees(ResupplyPair _pair) internal view returns (uint256 _claimableFees) {
        (, , _claimableFees, ) = _pair.previewAddInterest();
    }

    function __updateExchangeRateGetLow(ResupplyPair _pair) internal returns (uint256 _low) {
        uint256 _newLow = _pair.updateExchangeRate();
        _low = _newLow;
    }

    function __updateExchangeRateGetHigh(ResupplyPair _pair) internal returns (uint256 _high) {
        uint256 _newHigh = _pair.updateExchangeRate();
        _high = _newHigh;
    }

    function __getLowExchangeRate(ResupplyPair _pair) internal view returns (uint256 _low) {
        (, , _low ) = _pair.exchangeRateInfo();
    }

    function __getHighExchangeRate(ResupplyPair _pair) internal view returns (uint256 _high) {
        (, , _high) = _pair.exchangeRateInfo();
    }

    // function __getMaxOracleDeviation(ResupplyPair _pair) internal view returns (uint32 _maxOracleDeviation) {
    //     (, _maxOracleDeviation, , , ) = _pair.exchangeRateInfo();
    // }

    function __getOracle(ResupplyPair _pair) internal view returns (address _oracle) {
        (_oracle, , ) = _pair.exchangeRateInfo();
    }

    function __getUserSnapshot(
        ResupplyPair _pair,
        address _address
    ) external returns (uint256 _userBorrowShares, uint256 _userCollateralBalance) {
        _userBorrowShares = _pair.userBorrowShares(_address);
        _userCollateralBalance = _pair.userCollateralBalance(_address);
    }

    function __getPairAccounting(
        ResupplyPair _pair
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
        _claimableFees = _pair.claimableFees();
        (_totalBorrowAmount, _totalBorrowShares) = _pair.totalBorrow();
        _totalCollateral = _pair.totalCollateral();
    }
}
