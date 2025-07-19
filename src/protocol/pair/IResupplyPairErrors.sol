// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IResupplyPairErrors {
    error Insolvent(uint256 _borrow, uint256 _collateral, uint256 _exchangeRate);
    error BorrowerSolvent();
    error InsufficientDebtAvailable(uint256 _assets, uint256 _request);
    error SlippageTooHigh(uint256 _minOut, uint256 _actual);
    error BadSwapper();
    error InvalidReceiver();
    error InvalidLiquidator();
    error InvalidRedemptionHandler();
    error InvalidParameter();
    error InvalidPath(address _expected, address _actual);
    error InsufficientDebtToRedeem();
    error MinimumRedemption();
    error InsufficientBorrowAmount();
    error OnlyProtocolOrOwner();
    error InvalidOraclePrice();
    error FeesAlreadyDistributed();
    error IncorrectStakeBalance();
}