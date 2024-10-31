// SPDX-License-Identifier: ISC
pragma solidity >=0.8.19;

interface IResupplyPair {
    function CIRCUIT_BREAKER_ADDRESS() external view returns (address);

    function COMPTROLLER_ADDRESS() external view returns (address);

    function DEPLOYER_ADDRESS() external view returns (address);

    function FRAXLEND_WHITELIST_ADDRESS() external view returns (address);

    function timelockAddress() external view returns (address);

    function addCollateral(uint256 _collateralAmount, address _borrower) external;

    function addInterest()
        external
        returns (uint256 _interestEarned, uint256 _feesAmount, uint256 _feesShare, uint64 _newRate);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function approvedBorrowers(address) external view returns (bool);

    function approvedLenders(address) external view returns (bool);

    function asset() external view returns (address);

    function balanceOf(address account) external view returns (uint256);

    function borrowAsset(
        uint256 _borrowAmount,
        uint256 _collateralAmount,
        address _receiver
    ) external returns (uint256 _shares);

    function borrowerWhitelistActive() external view returns (bool);

    function changeFee(uint32 _newFee) external;

    function cleanLiquidationFee() external view returns (uint256);

    function collateralContract() external view returns (address);

    function currentRateInfo()
        external
        view
        returns (
            uint32 lastBlock,
            uint32 feeToProtocolRate,
            uint64 lastTimestamp,
            uint64 ratePerSec,
            uint64 fullUtilizationRate
        );

    function decimals() external view returns (uint8);

    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool);

    function deposit(uint256 _amount, address _receiver) external returns (uint256 _sharesReceived);

    function dirtyLiquidationFee() external view returns (uint256);

    function exchangeRateInfo() external view returns (uint32 lastTimestamp, uint224 exchangeRate);

    function getConstants()
        external
        pure
        returns (
            uint256 _LTV_PRECISION,
            uint256 _LIQ_PRECISION,
            uint256 _EXCHANGE_PRECISION,
            uint256 _RATE_PRECISION
        );

    function getPairAccounting()
        external
        view
        returns (
            uint256 _claimableFees,
            uint128 _totalBorrowAmount,
            uint128 _totalBorrowShares,
            uint256 _totalCollateral
        );

    function getUserSnapshot(
        address _address
    ) external view returns (uint256 _userBorrowShares, uint256 _userCollateralBalance);

    function increaseAllowance(address spender, uint256 addedValue) external returns (bool);

    function lenderWhitelistActive() external view returns (bool);

    function leveragedPosition(
        address _swapperAddress,
        uint256 _borrowAmount,
        uint256 _initialCollateralAmount,
        uint256 _amountCollateralOutMin,
        address[] memory _path
    ) external returns (uint256 _totalCollateralBalance);

    function liquidate(
        address _borrower
    ) external returns (uint256 _collateralForLiquidator);

    function maturityDate() external view returns (uint256);

    function maxLTV() external view returns (uint256);

    function name() external view returns (string memory);

    function owner() external view returns (address);

    function pause() external;

    function paused() external view returns (bool);

    function penaltyRate() external view returns (uint256);

    function rateContract() external view returns (address);

    function borrowLimit() external view returns (uint256);

    function redeem(uint256 _amount, uint256 _fee, address _redeemer) external returns(uint256 _collateralReturned);

    function removeCollateral(uint256 _collateralAmount, address _receiver) external;

    function renounceOwnership() external;

    function repayAsset(uint256 _shares, address _borrower) external returns (uint256 _amountToRepay);

    function repayAssetWithCollateral(
        address _swapperAddress,
        uint256 _collateralToSwap,
        uint256 _amountAssetOutMin,
        address[] memory _path
    ) external returns (uint256 _amountAssetOut);

    function setApprovedBorrowers(address[] memory _borrowers, bool _approval) external;

    function setApprovedLenders(address[] memory _lenders, bool _approval) external;

    function setMaxOracleDelay(uint256 _newDelay) external;

    function setSwapper(address _swapper, bool _approval) external;

    function setTimelock(address _newAddress) external;

    function swappers(address) external view returns (bool);

    function symbol() external view returns (string memory);

    function toAssetAmount(uint256 _shares, bool _roundUp) external view returns (uint256);

    function toAssetShares(uint256 _amount, bool _roundUp) external view returns (uint256);

    function toBorrowAmount(uint256 _shares, bool _roundUp) external view returns (uint256);

    function toBorrowShares(uint256 _amount, bool _roundUp) external view returns (uint256);

    function totalAsset() external view returns (uint128 amount, uint128 shares);

    function totalBorrow() external view returns (uint128 amount, uint128 shares);

    function totalCollateral() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);

    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    function transferOwnership(address newOwner) external;

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

}
