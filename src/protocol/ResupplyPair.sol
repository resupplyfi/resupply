// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

// ====================================================================
// |     ______                   _______                             |
// |    / _____________ __  __   / ____(_____  ____ _____  ________   |
// |   / /_  / ___/ __ `| |/_/  / /_  / / __ \/ __ `/ __ \/ ___/ _ \  |
// |  / __/ / /  / /_/ _>  <   / __/ / / / / / /_/ / / / / /__/  __/  |
// | /_/   /_/   \__,_/_/|_|  /_/   /_/_/ /_/\__,_/_/ /_/\___/\___/   |
// |                                                                  |
// ====================================================================
// ========================== ResupplyPair ============================
// ====================================================================
// Frax Finance: https://github.com/FraxFinance

// Primary Author
// Drake Evans: https://github.com/DrakeEvans

// Reviewers
// Dennis: https://github.com/denett
// Sam Kazemian: https://github.com/samkazemian
// Travis Moore: https://github.com/FortisFortuna
// Jack Corddry: https://github.com/corddry
// Rich Gee: https://github.com/zer0blockchain

// ====================================================================

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { ResupplyPairConstants } from "./pair/ResupplyPairConstants.sol";
import { ResupplyPairCore } from "./pair/ResupplyPairCore.sol";
import { SafeERC20 } from "../libraries/SafeERC20.sol";
import { VaultAccount, VaultAccountingLibrary } from "../libraries/VaultAccount.sol";
import { IRateCalculator } from "../interfaces/IRateCalculator.sol";
import { ISwapper } from "../interfaces/ISwapper.sol";
import { IFeeDeposit } from "../interfaces/IFeeDeposit.sol";
import { IResupplyRegistry } from "../interfaces/IResupplyRegistry.sol";
import { IConvexStaking } from "../interfaces/IConvexStaking.sol";
import { EpochTracker } from "../dependencies/EpochTracker.sol";
/// @title ResupplyPair
/// @author Drake Evans (Frax Finance) https://github.com/drakeevans
/// @notice  The ResupplyPair is a lending pair that allows users to engage in lending and borrowing activities
contract ResupplyPair is ResupplyPairCore, EpochTracker {
    using VaultAccountingLibrary for VaultAccount;
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    uint256 private constant WEEK = 7 * 86400;
    uint256 public lastFeeEpoch;
    address public constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address public constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;

    // Staking Info
    address public immutable convexBooster;
    uint256 public convexPid;
    
    error InvalidFeeTimestamp();
    error IncorrectStakeBalance();

    /// @param _configData config data
    /// @param _immutables immutable data
    /// @param _customConfigData extras
    constructor(
        address _core,
        bytes memory _configData,
        bytes memory _immutables,
        bytes memory _customConfigData
    ) ResupplyPairCore(_configData, _immutables, _customConfigData) EpochTracker(_core) {

        (, address _govToken, address _convexBooster, uint256 _convexpid) = abi.decode(
            _customConfigData,
            (string, address, address, uint256)
        );
        //add gov token rewards
        _insertRewardToken(_govToken);

        //convex info
        if(_convexBooster != address(0)){
            convexBooster = _convexBooster;
            convexPid = _convexpid;
            //approve
            collateralContract.approve(convexBooster, type(uint256).max);
            //add rewards for curve staking
            _insertRewardToken(CRV);
            _insertRewardToken(CVX);
        }
    }


    // ============================================================================================
    // Functions: Helpers
    // ============================================================================================

    function getConstants()
        external
        pure
        returns (
            uint256 _LTV_PRECISION,
            uint256 _LIQ_PRECISION,
            uint256 _EXCHANGE_PRECISION,
            uint256 _RATE_PRECISION
        )
    {
        _LTV_PRECISION = LTV_PRECISION;
        _LIQ_PRECISION = LIQ_PRECISION;
        _EXCHANGE_PRECISION = EXCHANGE_PRECISION;
        _RATE_PRECISION = RATE_PRECISION;
    }

    /// @notice The ```getUserSnapshot``` function gets user level accounting data
    /// @param _address The user address
    /// @return _userBorrowShares The user borrow shares
    /// @return _userCollateralBalance The user collateral balance
    function getUserSnapshot(
        address _address
    ) external returns (uint256 _userBorrowShares, uint256 _userCollateralBalance) {
        _userBorrowShares = userBorrowShares(_address);
        _userCollateralBalance = userCollateralBalance(_address);
    }

    /// @notice The ```getPairAccounting``` function gets all pair level accounting numbers
    /// @return _claimableFees Total claimable fees
    /// @return _totalBorrowAmount Total borrows
    /// @return _totalBorrowShares Total borrow shares
    /// @return _totalCollateral Total collateral
    function getPairAccounting()
        external
        view
        returns (
            uint256 _claimableFees,
            uint128 _totalBorrowAmount,
            uint128 _totalBorrowShares,
            uint256 _totalCollateral
        )
    {
        (, , uint256 _claimableFees, VaultAccount memory _totalBorrow) = previewAddInterest();
        _totalBorrowAmount = _totalBorrow.amount;
        _totalBorrowShares = _totalBorrow.shares;
        _totalCollateral = totalCollateral();
    }

    /// @notice The ```toBorrowShares``` function converts a given amount of borrow debt into the number of shares
    /// @param _amount Amount of borrow
    /// @param _roundUp Whether to roundup during division
    /// @param _previewInterest Whether to simulate interest accrual
    /// @return _shares The number of shares
    function toBorrowShares(
        uint256 _amount,
        bool _roundUp,
        bool _previewInterest
    ) external view returns (uint256 _shares) {
        if (_previewInterest) {
            (, , , VaultAccount memory _totalBorrow) = previewAddInterest();
            _shares = _totalBorrow.toShares(_amount, _roundUp);
        } else {
            _shares = totalBorrow.toShares(_amount, _roundUp);
        }
    }

    /// @notice The ```toBorrowAmount``` function converts a given amount of borrow debt into the number of shares
    /// @param _shares Shares of borrow
    /// @param _roundUp Whether to roundup during division
    /// @param _previewInterest Whether to simulate interest accrual
    /// @return _amount The amount of asset
    function toBorrowAmount(
        uint256 _shares,
        bool _roundUp,
        bool _previewInterest
    ) external view returns (uint256 _amount) {
        if (_previewInterest) {
            (, , , VaultAccount memory _totalBorrow) = previewAddInterest();
            _amount = _totalBorrow.toAmount(_shares, _roundUp);
        } else {
            _amount = totalBorrow.toAmount(_shares, _roundUp);
        }
    }
    // ============================================================================================
    // Functions: Configuration
    // ============================================================================================


    /// @notice The ```SetOracleInfo``` event is emitted when the oracle info (address and max deviation) is set
    /// @param oldOracle The old oracle address
    /// @param newOracle The new oracle address
    event SetOracleInfo(
        address oldOracle,
        address newOracle
    );

    /// @notice The ```setOracleInfo``` function sets the oracle data
    /// @param _newOracle The new oracle address
    function setOracle(address _newOracle) external {
        _requireProtocolOrOwner();
        ExchangeRateInfo memory _exchangeRateInfo = exchangeRateInfo;
        emit SetOracleInfo(
            _exchangeRateInfo.oracle,
            _newOracle
        );
        _exchangeRateInfo.oracle = _newOracle;
        exchangeRateInfo = _exchangeRateInfo;
    }

    /// @notice The ```SetMaxLTV``` event is emitted when the max LTV is set
    /// @param oldMaxLTV The old max LTV
    /// @param newMaxLTV The new max LTV
    event SetMaxLTV(uint256 oldMaxLTV, uint256 newMaxLTV);

    /// @notice The ```setMaxLTV``` function sets the max LTV
    /// @param _newMaxLTV The new max LTV
    function setMaxLTV(uint256 _newMaxLTV) external {
        _requireProtocolOrOwner();
        emit SetMaxLTV(maxLTV, _newMaxLTV);
        maxLTV = _newMaxLTV;
    }

 
    /// @notice The ```SetRateContract``` event is emitted when the rate contract is set
    /// @param oldRateContract The old rate contract
    /// @param newRateContract The new rate contract
    event SetRateContract(address oldRateContract, address newRateContract);

    /// @notice The ```setRateContract``` function sets the rate contract address
    /// @param _newRateContract The new rate contract address
    function setRateContract(address _newRateContract) external {
        _requireProtocolOrOwner();
        emit SetRateContract(address(rateContract), _newRateContract);
        rateContract = IRateCalculator(_newRateContract);
    }


    /// @notice The ```SetLiquidationFees``` event is emitted when the liquidation fees are set
    /// @param oldLiquidationFee The old clean liquidation fee
    /// @param newLiquidationFee The new clean liquidation fee
    event SetLiquidationFees(
        uint256 oldLiquidationFee,
        uint256 newLiquidationFee
    );

    /// @notice The ```setLiquidationFees``` function sets the liquidation fees
    /// @param _newLiquidationFee The new clean liquidation fee
    function setLiquidationFees(
        uint256 _newLiquidationFee
    ) external {
        _requireProtocolOrOwner();
        emit SetLiquidationFees(
            liquidationFee,
            _newLiquidationFee
        );
        liquidationFee = _newLiquidationFee;
    }

    /// @notice The ```SetMintFees``` event is emitted when the liquidation fees are set
    /// @param oldMintFee The old mint fee
    /// @param newMintFee The new mint fee
    event SetMintFees(
        uint256 oldMintFee,
        uint256 newMintFee
    );

    /// @notice The ```setMintFees``` function sets the mint
    /// @param _newMintFee The new mint fee
    function setMintFees(
        uint256 _newMintFee
    ) external {
        _requireProtocolOrOwner();
        emit SetMintFees(
            mintFee,
            _newMintFee
        );
        mintFee = _newMintFee;
    }

    /// @notice The ```SetBorrowLimit``` event is emitted when the borrow limit is set
    /// @param limit The new borrow limit
    event SetBorrowLimit(uint256 limit);

    function _setBorrowLimit(uint256 _limit) internal {
        borrowLimit = _limit;
        emit SetBorrowLimit(_limit);
    }

    event SetMinimumLeftover(uint256 min);

    function setMinimumLeftoverAssets(uint256 _min) internal {
        _requireProtocolOrOwner();
        minimumLeftoverAssets = _min;
        emit SetMinimumLeftover(_min);
    }

    event SetMinimumBorrowAmount(uint256 min);

    function setMinimumBorrowAmount(uint256 _min) internal {
        _requireProtocolOrOwner();
        minimumBorrowAmount = _min;
        emit SetMinimumBorrowAmount(_min);
    }

    event SetProtocolRedemptionFee(uint256 fee);

    function setProtocolRedemptionFee(uint256 _fee) internal {
        if(_fee > EXCHANGE_PRECISION) revert InvalidParameter();

        _requireProtocolOrOwner();
        protocolRedemptionFee = _fee;
        emit SetProtocolRedemptionFee(_fee);
    }

    /// @notice The ```WithdrawFees``` event fires when the fees are withdrawn
    /// @param recipient To whom the assets were sent
    /// @param interestFees the amount of interest based fees claimed
    /// @param otherFees the amount of other fees claimed(mint/redemption)
    event WithdrawFees(address recipient, uint256 interestFees, uint256 otherFees);

    /// @notice The ```withdrawFees``` function withdraws fees accumulated
    /// @return _fees the amount of interest based fees claimed
    /// @return _otherFees the amount of other fees claimed(mint/redemption)
    function withdrawFees() external nonReentrant returns (uint256 _fees, uint256 _otherFees) {

        // Accrue interest if necessary
        _addInterest();

        //get deposit contract
        address feeDeposit = IResupplyRegistry(registry).feeDeposit();
        uint256 depositEpoch = IFeeDeposit(feeDeposit).lastDistributedEpoch();
        uint256 currentEpoch = getEpoch();

        //current epoch must be greater than last claimed epoch
        //current epoch must be equal to the FeeDeposit prev distributed epoch (FeeDeposit must distribute first)
        if(currentEpoch <= lastFeeEpoch || currentEpoch != depositEpoch){
            revert InvalidFeeTimestamp();
        }

        //get fees and clear
        _fees = claimableFees;
        _otherFees = claimableOtherFees;
        claimableFees = 0;
        claimableOtherFees = 0;
        //mint new stables to the receiver
        IResupplyRegistry(registry).mint(feeDeposit,_fees+_otherFees);
        //inform deposit contract of this pair's contribution
        IFeeDeposit(feeDeposit).incrementPairRevenue(_fees,_otherFees);
        emit WithdrawFees(feeDeposit, _fees, _otherFees);
    }

    /// @notice The ```SetSwapper``` event fires whenever a swapper is black or whitelisted
    /// @param swapper The swapper address
    /// @param approval The approval
    event SetSwapper(address swapper, bool approval);

    /// @notice The ```setSwapper``` function is called to black or whitelist a given swapper address
    /// @dev
    /// @param _swapper The swapper address
    /// @param _approval The approval
    function setSwapper(address _swapper, bool _approval) external {
        _requireProtocolOrOwner();
        swappers[_swapper] = _approval;
        emit SetSwapper(_swapper, _approval);
    }

    /// @notice The ```SetConvexPool``` event fires when convex pool id is updated
    /// @param pid the convex pool id
    event SetConvexPool(uint256 pid);

    /// @notice The ```setConvexPool``` function is called update the underlying convex pool
    /// @dev
    /// @param pid the convex pool id
    function setConvexPool(uint256 pid) external {
        _requireProtocolOrOwner();
        _updateConvexPool(pid);
        emit SetConvexPool(pid);
    }

    function _updateConvexPool(uint256 _pid) internal{
        if(convexPid != _pid){
            //get previous staking
            (,,,address rewards,,) = IConvexStaking(convexBooster).poolInfo(convexPid);
            //get balance
            uint256 stakedBalance = IConvexStaking(rewards).balanceOf(address(this));
            
            if(stakedBalance > 0){
                //withdraw
                IConvexStaking(rewards).withdrawAndUnwrap(stakedBalance,false);
                if(collateralContract.balanceOf(address(this)) < stakedBalance){
                    revert IncorrectStakeBalance();
                }
            }

            //stake in new pool
            IConvexStaking(convexBooster).deposit(_pid, stakedBalance, true);

            //update pid
            convexPid = _pid;
        }
    }

    function _stakeUnderlying(uint256 _amount) internal override{
        if(convexPid != 0){
            IConvexStaking(convexBooster).deposit(convexPid, _amount, true);
        }
    }

    function _unstakeUnderlying(uint256 _amount) internal override{
        if(convexPid != 0){
            (,,,address rewards,,) = IConvexStaking(convexBooster).poolInfo(convexPid);
            IConvexStaking(rewards).withdrawAndUnwrap(_amount, false);
        }
    }

    function totalCollateral() public view override returns(uint256 _totalCollateralBalance){
        if(convexPid != 0){
            //get staking
            (,,,address rewards,,) = IConvexStaking(convexBooster).poolInfo(convexPid);
            //get balance
            _totalCollateralBalance = IConvexStaking(rewards).balanceOf(address(this));
        }else{
            _totalCollateralBalance = collateralContract.balanceOf(address(this));   
        }
    }

    // ============================================================================================
    // Functions: Access Control
    // ============================================================================================

    uint256 previousBorrowLimit;
    /// @notice The ```pause``` function is called to pause all contract functionality
    function pause() external {
        _requireProtocolOrOwner();
        previousBorrowLimit = borrowLimit;
        _setBorrowLimit(0);
    }

    /// @notice The ```unpause``` function is called to unpause all contract functionality
    function unpause() external {
        _requireProtocolOrOwner();
        _setBorrowLimit(previousBorrowLimit);
    }
}