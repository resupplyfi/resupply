pragma solidity 0.8.28;

import { IResupplyPairErrors } from "src/protocol/pair/IResupplyPairErrors.sol";

interface IResupplyPair is IResupplyPairErrors {
    
    struct CurrentRateInfo {
        uint64 lastTimestamp;
        uint64 ratePerSec;
        uint128 lastShares;
    }

    struct VaultAccount {
        uint128 amount;
        uint128 shares;
    }

    struct EarnedData {
        address token;
        uint256 amount;
    }

    function CRV(  ) external view returns (address ) ;
    function CVX(  ) external view returns (address ) ;
    function EXCHANGE_PRECISION(  ) external view returns (uint256 ) ;
    function LIQ_PRECISION(  ) external view returns (uint256 ) ;
    function LTV_PRECISION(  ) external view returns (uint256 ) ;
    function PAIR_DECIMALS(  ) external view returns (uint256 ) ;
    function RATE_PRECISION(  ) external view returns (uint256 ) ;
    function SHARE_REFACTOR_PRECISION(  ) external view returns (uint256 ) ;
    function addCollateral( uint256 _amount,address _borrower ) external   ;
    function addCollateralVault( uint256 _collateralAmount,address _borrower ) external   ;
    function addExtraReward( address _token ) external   ;
    function addInterest( bool _returnAccounting ) external  returns (uint256 _interestEarned, CurrentRateInfo memory _currentRateInfo, uint256 _claimableFees, VaultAccount memory _totalBorrow) ;
    function borrow( uint256 _borrowAmount,uint256 _underlyingAmount,address _receiver ) external  returns (uint256 _shares) ;
    function borrowLimit(  ) external view returns (uint256 ) ;
    function claimableFees(  ) external view returns (uint256 ) ;
    function claimableOtherFees(  ) external view returns (uint256 ) ;
    function claimable_reward( address ,address  ) external view returns (uint256 ) ;
    function collateral(  ) external view returns (address ) ;
    function convexBooster(  ) external view returns (address ) ;
    function convexPid(  ) external view returns (uint256 ) ;
    function core(  ) external view returns (address ) ;
    function currentRateInfo(  ) external view returns (uint64 lastTimestamp, uint64 ratePerSec, uint128 lastShares) ;
    function currentRewardEpoch(  ) external view returns (uint256 ) ;
    function currentUtilization(  ) external view returns (uint256 ) ;
    function earned( address _account ) external  returns (EarnedData[] memory claimable) ;
    function epochLength(  ) external view returns (uint256 ) ;
    function exchangeRateInfo(  ) external view returns (address oracle, uint96 lastTimestamp, uint256 exchangeRate) ;
    function getConstants(  ) external pure returns (uint256 _LTV_PRECISION, uint256 _LIQ_PRECISION, uint256 _EXCHANGE_PRECISION, uint256 _RATE_PRECISION) ;
    function getEpoch(  ) external view returns (uint256 epoch) ;
    function getPairAccounting(  ) external view returns (uint256 _claimableFees, uint128 _totalBorrowAmount, uint128 _totalBorrowShares, uint256 _totalCollateral) ;
    function getReward( address _account,address _forwardTo ) external   ;
    function getReward( address _account ) external   ;
    function getUserSnapshot( address _address ) external  returns (uint256 _borrowShares, uint256 _collateralBalance) ;
    function global_reward_integral( uint256 ,address  ) external view returns (uint256 ) ;
    function invalidateReward( address _token ) external   ;
    function lastFeeEpoch(  ) external view returns (uint256 ) ;
    function leveragedPosition( address _swapperAddress,uint256 _borrowAmount,uint256 _initialUnderlyingAmount,uint256 _amountCollateralOutMin,address[] memory _path ) external  returns (uint256 _totalCollateralBalance) ;
    function liquidate( address _borrower ) external  returns (uint256 _collateralForLiquidator) ;
    function liquidationFee(  ) external view returns (uint256 ) ;
    function maxLTV(  ) external view returns (uint256 ) ;
    function maxRewards(  ) external pure returns (uint256 ) ;
    function minimumBorrowAmount(  ) external view returns (uint256 ) ;
    function minimumLeftoverDebt(  ) external view returns (uint256 ) ;
    function minimumRedemption(  ) external view returns (uint256 ) ;
    function mintFee(  ) external view returns (uint256 ) ;
    function name(  ) external view returns (string memory ) ;
    function owner(  ) external view returns (address ) ;
    function pause(  ) external   ;
    function previewAddInterest(  ) external view returns (uint256 _interestEarned, CurrentRateInfo memory _newCurrentRateInfo, uint256 _claimableFees, VaultAccount memory _totalBorrow) ;
    function protocolRedemptionFee(  ) external view returns (uint256 ) ;
    function rateCalculator(  ) external view returns (address ) ;
    function redeemCollateral( address _caller,uint256 _amount,uint256 _totalFeePct,address _receiver ) external  returns (address _collateralToken, uint256 _collateralFreed) ;
    function redemptionWriteOff(  ) external view returns (address ) ;
    function registry(  ) external view returns (address ) ;
    function removeCollateral( uint256 _collateralAmount,address _receiver ) external   ;
    function removeCollateralVault( uint256 _collateralAmount,address _receiver ) external   ;
    function repay( uint256 _shares,address _borrower ) external  returns (uint256 _amountToRepay) ;
    function repayWithCollateral( address _swapperAddress,uint256 _collateralToSwap,uint256 _amountOutMin,address[] memory _path ) external  returns (uint256 _amountOut) ;
    function rewardLength(  ) external view returns (uint256 ) ;
    function rewardMap( address  ) external view returns (uint256 ) ;
    function rewardRedirect( address  ) external view returns (address ) ;
    function reward_integral_for( uint256 ,address ,address  ) external view returns (uint256 ) ;
    function rewards( uint256  ) external view returns (address reward_token, bool is_non_claimable, uint256 reward_remaining) ;
    function setBorrowLimit( uint256 _limit ) external   ;
    function setConvexPool( uint256 pid ) external   ;
    function setLiquidationFees( uint256 _newLiquidationFee ) external   ;
    function setMaxLTV( uint256 _newMaxLTV ) external   ;
    function setMinimumBorrowAmount( uint256 _min ) external   ;
    function setMinimumLeftoverDebt( uint256 _min ) external   ;
    function setMinimumRedemption( uint256 _min ) external   ;
    function setMintFees( uint256 _newMintFee ) external   ;
    function setOracle( address _newOracle ) external   ;
    function setProtocolRedemptionFee( uint256 _fee ) external   ;
    function setRateCalculator( address _newRateCalculator,bool _updateInterest ) external   ;
    function setRewardRedirect( address _to ) external   ;
    function setSwapper( address _swapper,bool _approval ) external   ;
    function startTime(  ) external view returns (uint256 ) ;
    function swappers( address  ) external view returns (bool ) ;
    function toBorrowAmount( uint256 _shares,bool _roundUp,bool _previewInterest ) external view returns (uint256 _amount) ;
    function toBorrowShares( uint256 _amount,bool _roundUp,bool _previewInterest ) external view returns (uint256 _shares) ;
    function totalBorrow(  ) external view returns (uint128 amount, uint128 shares) ;
    function totalCollateral(  ) external view returns (uint256 _totalCollateralBalance) ;
    function totalDebtAvailable(  ) external view returns (uint256 ) ;
    function underlying(  ) external view returns (address ) ;
    function unpause(  ) external   ;
    function updateExchangeRate(  ) external  returns (uint256 _exchangeRate) ;
    function userBorrowShares( address _account ) external view returns (uint256 borrowShares) ;
    function userCollateralBalance( address _account ) external  returns (uint256 _collateralAmount) ;
    function userRewardEpoch( address  ) external view returns (uint256 ) ;
    function user_checkpoint( address _account,uint256 _epochloops ) external  returns (bool ) ;
    function version(  ) external pure returns (uint256 _major, uint256 _minor, uint256 _patch) ;
    function withdrawFees(  ) external  returns (uint256 _fees, uint256 _otherFees) ;

    event AddCollateral( address indexed borrower,uint256 collateralAmount ) ;
    event AddInterest( uint256 interestEarned,uint256 rate ) ;
    event Borrow( address indexed _borrower,address indexed _receiver,uint256 _borrowAmount,uint256 _sharesAdded,uint256 _mintFees ) ;
    event LeveragedPosition( address indexed _borrower,address _swapperAddress,uint256 _borrowAmount,uint256 _borrowShares,uint256 _initialUnderlyingAmount,uint256 _amountCollateralOut ) ;
    event Liquidate( address indexed _borrower,uint256 _collateralForLiquidator,uint256 _sharesLiquidated,uint256 _amountLiquidatorToRepay ) ;
    event NewEpoch( uint256 indexed _epoch ) ;
    event Redeemed( address indexed _caller,uint256 _amount,uint256 _collateralFreed,uint256 _protocolFee,uint256 _debtReduction ) ;
    event RemoveCollateral( uint256 _collateralAmount,address indexed _receiver,address indexed _borrower ) ;
    event Repay( address indexed payer,address indexed borrower,uint256 amountToRepay,uint256 shares ) ;
    event RepayWithCollateral( address indexed _borrower,address _swapperAddress,uint256 _collateralToSwap,uint256 _amountAssetOut,uint256 _sharesRepaid ) ;
    event RewardAdded( address indexed _rewardToken ) ;
    event RewardInvalidated( address indexed _rewardToken ) ;
    event RewardPaid( address indexed _user,address indexed _rewardToken,address indexed _receiver,uint256 _rewardAmount ) ;
    event RewardRedirected( address indexed _account,address _forward ) ;
    event SetBorrowLimit( uint256 limit ) ;
    event SetConvexPool( uint256 pid ) ;
    event SetLiquidationFees( uint256 oldLiquidationFee,uint256 newLiquidationFee ) ;
    event SetMaxLTV( uint256 oldMaxLTV,uint256 newMaxLTV ) ;
    event SetMinimumBorrowAmount( uint256 min ) ;
    event SetMinimumLeftover( uint256 min ) ;
    event SetMinimumRedemption( uint256 min ) ;
    event SetMintFees( uint256 oldMintFee,uint256 newMintFee ) ;
    event SetOracleInfo( address oldOracle,address newOracle ) ;
    event SetProtocolRedemptionFee( uint256 fee ) ;
    event SetRateCalculator( address oldRateCalculator,address newRateCalculator ) ;
    event SetSwapper( address swapper,bool approval ) ;
    event UpdateExchangeRate( uint256 exchangeRate ) ;
    event UpdateRate( uint256 oldRatePerSec,uint128 oldShares,uint256 newRatePerSec,uint128 newShares ) ;
    event WithdrawFees( address recipient,uint256 interestFees,uint256 otherFees ) ;
}