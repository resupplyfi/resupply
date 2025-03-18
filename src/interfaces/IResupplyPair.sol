// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IResupplyPair {
    struct CurrentRateInfo {
        uint64 lastTimestamp;
        uint64 ratePerSec;
        uint256 lastShares;
    }
    struct VaultAccount {
        uint128 amount;
        uint128 shares;
    }
    function addCollateral(uint256 _collateralAmount, address _borrower) external;
    function addCollateralUnderlying(uint256 _collateralAmount, address _borrower) external;
    function addInterest()
        external
        returns (uint256 _interestEarned, uint256 _feesAmount, uint256 _feesShare, uint64 _newRate);
    function asset() external view returns (address);
    function balanceOf(address account) external view returns (uint256);
    function borrow(
        uint256 _borrowAmount,
        uint256 _collateralAmount,
        address _receiver
    ) external returns (uint256 _shares);

    function changeFee(uint32 _newFee) external;
    function mintFee() external view returns (uint256);
    function liquidationFee() external view returns (uint256);
    function protocolRedemptionFee() external view returns (uint256);
    function collateral() external view returns (address);
    function underlying() external view returns (address);
    function currentRateInfo() external view returns (
        uint32 lastBlock,
        uint64 lastTimestamp,
        uint64 ratePerSec,
        uint256 lastPrice,
        uint256 lastShares
    );
    function previewAddInterest() external view returns (
        uint256 _interestEarned,
        CurrentRateInfo memory _newCurrentRateInfo,
        uint256 _claimableFees,
        VaultAccount memory _totalBorrow
    );
    function exchangeRateInfo() external view returns (address oracle, uint32 lastTimestamp, uint224 exchangeRate);
    function getConstants() external pure returns (
        uint256 _LTV_PRECISION,
        uint256 _LIQ_PRECISION,
        uint256 _EXCHANGE_PRECISION,
        uint256 _RATE_PRECISION
    );
    function getPairAccounting() external view returns (
        uint256 _claimableFees,
        uint128 _totalBorrowAmount,
        uint128 _totalBorrowShares,
        uint256 _totalCollateral
    );
    function getUserSnapshot(address _address) external view returns (uint256 _userBorrowShares, uint256 _userCollateralBalance);
    function leveragePosition(
        address _swapperAddress,
        uint256 _borrowAmount,
        uint256 _initialUnderlyingAmount,
        uint256 _amountCollateralOutMin,
        address[] memory _path
    ) external returns (uint256 _totalCollateralBalance);
    function liquidate(address _borrower) external returns (uint256 _collateralForLiquidator);
    function maxLTV() external view returns (uint256);
    function name() external view returns (string memory);
    function owner() external view returns (address);
    function pause() external;
    function paused() external view returns (bool);
    function rateCalculator() external view returns (address);
    function borrowLimit() external view returns (uint256);
    function totalAssetAvailable() external view returns (uint256);
    function minimumLeftoverDebt() external view returns (uint256);
    function minimumBorrowAmount() external view returns (uint256);
    function minimumRedemption() external view returns (uint256);
    function redeemCollateral(address _caller, uint256 _amount, uint256 _fee, address _receiver) external returns(address _collateralToken, uint256 _collateralReturned);
    function removeCollateral(uint256 _collateralAmount, address _receiver) external;
    function renounceOwnership() external;
    function repayAsset(uint256 _shares, address _borrower) external returns (uint256 _amountToRepay);
    function repayAssetWithCollateral(
        address _swapperAddress,
        uint256 _collateralToSwap,
        uint256 _amountAssetOutMin,
        address[] memory _path
    ) external returns (uint256 _amountAssetOut);
    function setBorrowLimit(uint256 _limit) external;
    function setApprovedBorrowers(address[] memory _borrowers, bool _approval) external;
    function setApprovedLenders(address[] memory _lenders, bool _approval) external;
    function setMaxOracleDelay(uint256 _newDelay) external;
    function setSwapper(address _swapper, bool _approval) external;
    function swappers(address) external view returns (bool);
    function symbol() external view returns (string memory);
    function toBorrowAmount(uint256 _shares, bool _roundUp, bool _previewInterest) external view returns (uint256);
    function toBorrowShares(uint256 _amount, bool _roundUp, bool _previewInterest) external view returns (uint256);
    function totalBorrow() external view returns (uint128 amount, uint128 shares);
    function totalCollateral() external view returns (uint256);
    function unpause() external;
    function updateExchangeRate() external returns (uint256 _exchangeRate);
    function userBorrowShares(address) external view returns (uint256);
    function userCollateralBalance(address) external returns (uint256);
    function version() external pure returns (uint256 _major, uint256 _minor, uint256 _patch);
    function withdrawFees() external returns (uint256 _amountToTransfer);
    function convexBooster() external view returns (address convexBooster);
    function convexPid() external view returns (uint256 _convexPid);
    function rewardLength() external view returns (uint256 _length);
    function rewardMap(address _reward) external view returns (uint256 _rewardSlot);
    function addExtraReward(address _token) external;
    function earned(address _account) external returns(EarnedData[] memory claimable);
    function setOracle(address _newOracle) external;
    function setMaxLTV(uint256 _newMaxLTV) external;
    function setRateCalculator(address _newRateCalculator, bool _updateInterest) external;
    function setLiquidationFees(uint256 _newLiquidationFee) external;
    function setMintFees(uint256 _newMintFee) external;
    function setMinimumRedemption(uint256 _min) external;
    function setMinimumLeftoverDebt(uint256 _min) external;
    function setMinimumBorrowAmount(uint256 _min) external;
    function setProtocolRedemptionFee(uint256 _fee) external;
    function setConvexPool(uint256 pid) external;
    function CRV() external pure returns (address);
    function CVX() external pure returns (address);

    struct EarnedData {
        address token;
        uint256 amount;
    }

    // Events
    event SetOracleInfo(address oldOracle, address newOracle);
    event SetMaxLTV(uint256 oldMaxLTV, uint256 newMaxLTV);
    event SetRateCalculator(address oldRateCalculator, address newRateCalculator);
    event SetLiquidationFees(uint256 oldLiquidationFee, uint256 newLiquidationFee);
    event SetMintFees(uint256 oldMintFee, uint256 newMintFee);
    event SetBorrowLimit(uint256 limit);
    event SetMinimumRedemption(uint256 min);
    event SetMinimumLeftover(uint256 min);
    event SetMinimumBorrowAmount(uint256 min);
    event SetProtocolRedemptionFee(uint256 fee);
    event WithdrawFees(address recipient, uint256 interestFees, uint256 otherFees);
    event SetSwapper(address swapper, bool approval);
    event SetConvexPool(uint256 pid);

    // Errors
    error FeesAlreadyDistributed();
    error IncorrectStakeBalance();
    error InvalidParameter();
    error OnlyProtocolOrOwner();
}
