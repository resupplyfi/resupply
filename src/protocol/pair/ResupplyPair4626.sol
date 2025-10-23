// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title ResupplyPair
 * @notice Based on code from Drake Evans and Frax Finance's lending pair contract (https://github.com/FraxFinance/fraxlend), adapted for Resupply Finance
 */

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { ResupplyPairCore } from "src/protocol/pair/ResupplyPairCore.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { VaultAccount, VaultAccountingLibrary } from "src/libraries/VaultAccount.sol";
import { IRateCalculator } from "src/interfaces/IRateCalculator.sol";
import { ISwapper } from "src/interfaces/ISwapper.sol";
import { IFeeDeposit } from "src/interfaces/IFeeDeposit.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { EpochTracker } from "src/dependencies/EpochTracker.sol";

contract ResupplyPair is ResupplyPairCore, EpochTracker {
    using VaultAccountingLibrary for VaultAccount;
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    address public immutable vault;
    uint256 public lastFeeEpoch;

    /// @param _core Core contract address
    /// @param _configData config data
    /// @param _immutables immutable data
    /// @param _customConfigData extras
    constructor(
        address _core,
        bytes memory _configData,
        bytes memory _immutables,
        bytes memory _customConfigData
    ) ResupplyPairCore(_core, _configData, _immutables, _customConfigData) EpochTracker(_core) {
        (address _govToken, address _vault) = abi.decode(
            _customConfigData,
            (address, address)
        );
        _insertRewardToken(_govToken);
        vault = _vault;
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
    /// @return _borrowShares The user borrow shares
    /// @return _collateralBalance The user collateral balance
    function getUserSnapshot(
        address _address
    ) external returns (uint256 _borrowShares, uint256 _collateralBalance) {
        _collateralBalance = userCollateralBalance(_address);
        _borrowShares = userBorrowShares(_address);
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
        VaultAccount memory _totalBorrow;
        (, , _claimableFees, _totalBorrow) = previewAddInterest();
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


    /// @notice The ```SetOracleInfo``` event is emitted when the oracle info is set
    /// @param oldOracle The old oracle address
    /// @param newOracle The new oracle address
    event SetOracleInfo(
        address oldOracle,
        address newOracle
    );

    /// @notice The ```setOracleInfo``` function sets the oracle data
    /// @param _newOracle The new oracle address
    function setOracle(address _newOracle) external onlyOwner{
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
    function setMaxLTV(uint256 _newMaxLTV) external onlyOwner{
        if (_newMaxLTV > LTV_PRECISION) revert InvalidParameter();
        emit SetMaxLTV(maxLTV, _newMaxLTV);
        maxLTV = _newMaxLTV;
    }

 
    /// @notice The ```SetRateCalculator``` event is emitted when the rate contract is set
    /// @param oldRateCalculator The old rate contract
    /// @param newRateCalculator The new rate contract
    event SetRateCalculator(address oldRateCalculator, address newRateCalculator);

    /// @notice The ```setRateCalculator``` function sets the rate contract address
    /// @param _newRateCalculator The new rate contract address
    /// @param _updateInterest Whether to update interest before setting new rate calculator
    function setRateCalculator(address _newRateCalculator, bool _updateInterest) external onlyOwner{
        //should add interest before changing rate calculator
        //however if there is an intrinsic problem with the current rate calculate, need to be able
        //to update without calling addInterest
        if(_updateInterest){
            _addInterest();
        }
        emit SetRateCalculator(address(rateCalculator), _newRateCalculator);
        rateCalculator = IRateCalculator(_newRateCalculator);
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
    ) external onlyOwner{
        if (_newLiquidationFee > LIQ_PRECISION) revert InvalidParameter();
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
    ) external onlyOwner{
        emit SetMintFees(
            mintFee,
            _newMintFee
        );
        mintFee = _newMintFee;
    }

    function setBorrowLimit(uint256 _limit) external onlyOwner{
        _setBorrowLimit(_limit);
    }

    /// @notice The ```SetBorrowLimit``` event is emitted when the borrow limit is set
    /// @param limit The new borrow limit
    event SetBorrowLimit(uint256 limit);

    function _setBorrowLimit(uint256 _limit) internal {
        if(_limit > type(uint128).max){
            revert InvalidParameter();
        }
        borrowLimit = _limit;
        emit SetBorrowLimit(_limit);
    }

    event SetMinimumRedemption(uint256 min);

    function setMinimumRedemption(uint256 _min) external onlyOwner{
        if(_min < 100 * PAIR_DECIMALS ){
            revert InvalidParameter();
        }
        minimumRedemption = _min;
        emit SetMinimumRedemption(_min);
    }

    event SetMinimumLeftover(uint256 min);

    function setMinimumLeftoverDebt(uint256 _min) external onlyOwner{
        minimumLeftoverDebt = _min;
        emit SetMinimumLeftover(_min);
    }

    event SetMinimumBorrowAmount(uint256 min);

    function setMinimumBorrowAmount(uint256 _min) external onlyOwner{
        minimumBorrowAmount = _min;
        emit SetMinimumBorrowAmount(_min);
    }

    event SetProtocolRedemptionFee(uint256 fee);

    /// @notice Sets the redemption fee percentage for this specific pair
    /// @dev The fee is 1e18 precision (1e16 = 1%) and taken from redemptions and sent to the protocol.
    /// @param _fee The new redemption fee percentage. Must be less than or equal to 1e18 (100%)
    function setProtocolRedemptionFee(uint256 _fee) external onlyOwner{
        if(_fee > EXCHANGE_PRECISION) revert InvalidParameter();

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
        uint256 lastDistributedEpoch = IFeeDeposit(feeDeposit).lastDistributedEpoch();
        uint256 currentEpoch = getEpoch();

        //current epoch must be greater than last claimed epoch
        //current epoch must be equal to the FeeDeposit prev distributed epoch (FeeDeposit must distribute first)
        if(currentEpoch <= lastFeeEpoch || currentEpoch != lastDistributedEpoch){
            revert FeesAlreadyDistributed();
        }

        lastFeeEpoch = currentEpoch;

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
    function setSwapper(address _swapper, bool _approval) external{
        if(msg.sender == owner() || msg.sender == registry){
            swappers[_swapper] = _approval;
            emit SetSwapper(_swapper, _approval);
        }else{
            revert OnlyProtocolOrOwner();
        }
    }

    function totalCollateral() public view override returns(uint256 _totalCollateralBalance){
        _totalCollateralBalance = IERC4626(vault).convertToAssets(IERC20(vault).balanceOf(address(this)));
    }

    // ============================================================================================
    // Functions: Access Control
    // ============================================================================================

    uint256 previousBorrowLimit;
    /// @notice The ```pause``` function is called to pause all contract functionality
    function pause() external onlyOwner{
        if (borrowLimit > 0) {
            previousBorrowLimit = borrowLimit;
            _setBorrowLimit(0);
        }
    }

    /// @notice The ```unpause``` function is called to unpause all contract functionality
    function unpause() external onlyOwner{
        if (borrowLimit == 0) _setBorrowLimit(previousBorrowLimit);
    }

    function _stakeUnderlying(uint256 _amount) internal override {}

    function _unstakeUnderlying(uint256 _amount) internal override {}
}