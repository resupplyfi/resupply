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
// ========================== FraxlendPair ============================
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
// import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FraxlendPairConstants } from "./FraxlendPairConstants.sol";
import { FraxlendPairCore } from "./FraxlendPairCore.sol";
import { Timelock2Step } from "./Timelock2Step.sol";
import { SafeERC20 } from "../../libraries/SafeERC20.sol";
import { VaultAccount, VaultAccountingLibrary } from "../../libraries/VaultAccount.sol";
import { IRateCalculator } from "../../interfaces/IRateCalculator.sol";
import { ISwapper } from "../../interfaces/ISwapper.sol";
import { IFeeDeposit } from "../../interfaces/IFeeDeposit.sol";
import { IPairRegistry } from "../../interfaces/IPairRegistry.sol";

/// @title FraxlendPair
/// @author Drake Evans (Frax Finance) https://github.com/drakeevans
/// @notice  The FraxlendPair is a lending pair that allows users to engage in lending and borrowing activities
contract FraxlendPair is FraxlendPairCore {
    using VaultAccountingLibrary for VaultAccount;
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    /// @param _configData abi.encode(address _asset, address _collateral, address _oracle, uint32 _maxOracleDeviation, address _rateContract, uint64 _fullUtilizationRate, uint256 _maxLTV, uint256 _cleanLiquidationFee, uint256 _dirtyLiquidationFee, uint256 _protocolLiquidationFee)
    /// @param _immutables abi.encode(address _circuitBreakerAddress, address _comptrollerAddress, address _timelockAddress)
    /// @param _customConfigData abi.encode(string memory _nameOfContract, string memory _symbolOfContract, uint8 _decimalsOfContract)
    constructor(
        bytes memory _configData,
        bytes memory _immutables,
        bytes memory _customConfigData
    ) FraxlendPairCore(_configData, _immutables, _customConfigData) {}


    // ============================================================================================
    // Functions: Helpers
    // ============================================================================================

    function asset() external view returns (address) {
        return address(assetContract);
    }

    function getConstants()
        external
        pure
        returns (
            uint256 _LTV_PRECISION,
            uint256 _LIQ_PRECISION,
            uint256 _UTIL_PREC,
            uint256 _FEE_PRECISION,
            uint256 _EXCHANGE_PRECISION,
            uint256 _DEVIATION_PRECISION,
            uint256 _RATE_PRECISION,
            uint256 _MAX_PROTOCOL_FEE
        )
    {
        _LTV_PRECISION = LTV_PRECISION;
        _LIQ_PRECISION = LIQ_PRECISION;
        _UTIL_PREC = UTIL_PREC;
        _FEE_PRECISION = FEE_PRECISION;
        _EXCHANGE_PRECISION = EXCHANGE_PRECISION;
        _DEVIATION_PRECISION = DEVIATION_PRECISION;
        _RATE_PRECISION = RATE_PRECISION;
        _MAX_PROTOCOL_FEE = MAX_PROTOCOL_FEE;
    }

    /// @notice The ```getUserSnapshot``` function gets user level accounting data
    /// @param _address The user address
    /// @return _userBorrowShares The user borrow shares
    /// @return _userCollateralBalance The user collateral balance
    function getUserSnapshot(
        address _address
    ) external view returns (uint256 _userBorrowShares, uint256 _userCollateralBalance) {
        _userBorrowShares = userBorrowShares[_address];
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
        _totalCollateral = totalCollateral;
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

    bool public isOracleSetterRevoked;

    /// @notice The ```RevokeOracleSetter``` event is emitted when the oracle setter is revoked
    event RevokeOracleInfoSetter();

    /// @notice The ```revokeOracleSetter``` function revokes the oracle setter
    function revokeOracleInfoSetter() external {
        _requireProtocolOrOwner();
        isOracleSetterRevoked = true;
        emit RevokeOracleInfoSetter();
    }

    /// @notice The ```SetOracleInfo``` event is emitted when the oracle info (address and max deviation) is set
    /// @param oldOracle The old oracle address
    /// @param oldMaxOracleDeviation The old max oracle deviation
    /// @param newOracle The new oracle address
    /// @param newMaxOracleDeviation The new max oracle deviation
    event SetOracleInfo(
        address oldOracle,
        uint32 oldMaxOracleDeviation,
        address newOracle,
        uint32 newMaxOracleDeviation
    );

    /// @notice The ```setOracleInfo``` function sets the oracle data
    /// @param _newOracle The new oracle address
    /// @param _newMaxOracleDeviation The new max oracle deviation
    function setOracle(address _newOracle, uint32 _newMaxOracleDeviation) external {
        _requireProtocolOrOwner();
        if (isOracleSetterRevoked) revert SetterRevoked();
        ExchangeRateInfo memory _exchangeRateInfo = exchangeRateInfo;
        emit SetOracleInfo(
            _exchangeRateInfo.oracle,
            _exchangeRateInfo.maxOracleDeviation,
            _newOracle,
            _newMaxOracleDeviation
        );
        _exchangeRateInfo.oracle = _newOracle;
        _exchangeRateInfo.maxOracleDeviation = _newMaxOracleDeviation;
        exchangeRateInfo = _exchangeRateInfo;
    }

    bool public isMaxLTVSetterRevoked;

    /// @notice The ```RevokeMaxLTVSetter``` event is emitted when the max LTV setter is revoked
    event RevokeMaxLTVSetter();

    /// @notice The ```revokeMaxLTVSetter``` function revokes the max LTV setter
    function revokeMaxLTVSetter() external {
        _requireProtocolOrOwner();
        isMaxLTVSetterRevoked = true;
        emit RevokeMaxLTVSetter();
    }

    /// @notice The ```SetMaxLTV``` event is emitted when the max LTV is set
    /// @param oldMaxLTV The old max LTV
    /// @param newMaxLTV The new max LTV
    event SetMaxLTV(uint256 oldMaxLTV, uint256 newMaxLTV);

    /// @notice The ```setMaxLTV``` function sets the max LTV
    /// @param _newMaxLTV The new max LTV
    function setMaxLTV(uint256 _newMaxLTV) external {
        _requireProtocolOrOwner();
        if (isMaxLTVSetterRevoked) revert SetterRevoked();
        emit SetMaxLTV(maxLTV, _newMaxLTV);
        maxLTV = _newMaxLTV;
    }

    bool public isRateContractSetterRevoked;

    /// @notice The ```RevokeRateContractSetter``` event is emitted when the rate contract setter is revoked
    event RevokeRateContractSetter();

    /// @notice The ```revokeRateContractSetter``` function revokes the rate contract setter
    function revokeRateContractSetter() external {
        _requireProtocolOrOwner();
        isRateContractSetterRevoked = true;
        emit RevokeRateContractSetter();
    }

    /// @notice The ```SetRateContract``` event is emitted when the rate contract is set
    /// @param oldRateContract The old rate contract
    /// @param newRateContract The new rate contract
    event SetRateContract(address oldRateContract, address newRateContract);

    /// @notice The ```setRateContract``` function sets the rate contract address
    /// @param _newRateContract The new rate contract address
    function setRateContract(address _newRateContract) external {
        _requireProtocolOrOwner();
        if (isRateContractSetterRevoked) revert SetterRevoked();
        emit SetRateContract(address(rateContract), _newRateContract);
        rateContract = IRateCalculator(_newRateContract);
    }

    bool public isLiquidationFeeSetterRevoked;

    /// @notice The ```RevokeLiquidationFeeSetter``` event is emitted when the liquidation fee setter is revoked
    event RevokeLiquidationFeeSetter();

    /// @notice The ```revokeLiquidationFeeSetter``` function revokes the liquidation fee setter
    function revokeLiquidationFeeSetter() external {
        _requireProtocolOrOwner();
        isLiquidationFeeSetterRevoked = true;
        emit RevokeLiquidationFeeSetter();
    }

    /// @notice The ```SetLiquidationFees``` event is emitted when the liquidation fees are set
    /// @param oldLiquidationFee The old clean liquidation fee
    /// @param newLiquidationFee The new clean liquidation fee
    event SetLiquidationFees(
        uint256 oldLiquidationFee,
        // uint256 oldDirtyLiquidationFee,
        // uint256 oldProtocolLiquidationFee,
        uint256 newLiquidationFee
        // uint256 newDirtyLiquidationFee,
        // uint256 newProtocolLiquidationFee
    );

    /// @notice The ```setLiquidationFees``` function sets the liquidation fees
    /// @param _newLiquidationFee The new clean liquidation fee
    function setLiquidationFees(
        uint256 _newLiquidationFee
        // uint256 _newDirtyLiquidationFee,
        // uint256 _newProtocolLiquidationFee
    ) external {
        _requireProtocolOrOwner();
        if (isLiquidationFeeSetterRevoked) revert SetterRevoked();
        emit SetLiquidationFees(
            liquidationFee,
            // dirtyLiquidationFee,
            // protocolLiquidationFee,
            _newLiquidationFee
            // _newDirtyLiquidationFee,
            // _newProtocolLiquidationFee
        );
        liquidationFee = _newLiquidationFee;
        // dirtyLiquidationFee = _newDirtyLiquidationFee;
        // protocolLiquidationFee = _newProtocolLiquidationFee;
    }

    /// @notice The ```WithdrawFees``` event fires when the fees are withdrawn
    /// @param recipient To whom the assets were sent
    /// @param amountToTransfer The amount of fees redeemed
    event WithdrawFees(address recipient, uint256 amountToTransfer);

    /// @notice The ```withdrawFees``` function withdraws fees accumulated
    /// @return _amountToTransfer Amount of assets sent to recipient
    function withdrawFees() external nonReentrant returns (uint256 _amountToTransfer) {

        // Accrue interest if necessary
        _addInterest();

        //get deposit contract
        address feeDeposit = IPairRegistry(registry).feeDeposit();
        //check fees and clear
        uint256 _amountToTransfer = claimableFees;
        claimableFees = 0;
        //mint new stables to the receiver
        IPairRegistry(registry).mint(feeDeposit,_amountToTransfer);
        //inform deposit contract of this pair's contribution
        IFeeDeposit(feeDeposit).incrementPairRevenue(_amountToTransfer);
        emit WithdrawFees(feeDeposit, _amountToTransfer);
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

    // ============================================================================================
    // Functions: Access Control
    // ============================================================================================

    uint256 previousBorrowLimit;
    /// @notice The ```pause``` function is called to pause all contract functionality
    function pause() external {
        _requireProtocolOrOwner();
        previousBorrowLimit = borrowLimit;
        _setBorrowLimit(0);
        // if (!isDepositAccessControlRevoked) _setDepositLimit(0);
        if (!isRepayAccessControlRevoked) _pauseRepay(true);
        if (!isWithdrawAccessControlRevoked) _pauseWithdraw(true);
        if (!isLiquidateAccessControlRevoked) _pauseLiquidate(true);
        if (!isInterestAccessControlRevoked) {
            _addInterest();
            _pauseInterest(true);
        }
    }

    /// @notice The ```unpause``` function is called to unpause all contract functionality
    function unpause() external {
        _requireProtocolOrOwner();
        _setBorrowLimit(previousBorrowLimit);
        // if (!isDepositAccessControlRevoked) _setDepositLimit(type(uint256).max);
        if (!isRepayAccessControlRevoked) _pauseRepay(false);
        if (!isWithdrawAccessControlRevoked) _pauseWithdraw(false);
        if (!isLiquidateAccessControlRevoked) _pauseLiquidate(false);
        if (!isInterestAccessControlRevoked) {
            _addInterest();
            _pauseInterest(false);
        }
    }

    /// @notice The ```pauseBorrow``` function sets borrow limit to 0
    function pauseBorrow() external {
        _requireProtocolOrOwner();
        // if (isBorrowAccessControlRevoked) revert AccessControlRevoked();
        _setBorrowLimit(0);
    }

    /// @notice The ```setBorrowLimit``` function sets the borrow limit
    /// @param _limit The new borrow limit
    function setBorrowLimit(uint256 _limit) external {
        _requireProtocolOrOwner();
        // if (isBorrowAccessControlRevoked) revert AccessControlRevoked();
        _setBorrowLimit(_limit);
        previousBorrowLimit = _limit;
    }

    // /// @notice The ```revokeBorrowLimitAccessControl``` function revokes borrow limit access control
    // /// @param _borrowLimit The new borrow limit
    // function revokeBorrowLimitAccessControl(uint256 _borrowLimit) external {
    //     _requireProtocolOrOwner();
    //     _revokeBorrowAccessControl(_borrowLimit);
    // }

    // /// @notice The ```pauseDeposit``` function pauses deposit functionality
    // function pauseDeposit() external {
    //     _requireProtocolOrOwner();
    //     if (isDepositAccessControlRevoked) revert AccessControlRevoked();
    //     _setDepositLimit(0);
    // }

    // /// @notice The ```setDepositLimit``` function sets the deposit limit
    // /// @param _limit The new deposit limit
    // function setDepositLimit(uint256 _limit) external {
    //     _requireTimelockOrOwner();
    //     if (isDepositAccessControlRevoked) revert AccessControlRevoked();
    //     _setDepositLimit(_limit);
    // }

    // /// @notice The ```revokeDepositLimitAccessControl``` function revokes deposit limit access control
    // /// @param _depositLimit The new deposit limit
    // function revokeDepositLimitAccessControl(uint256 _depositLimit) external {
    //     _requireTimelock();
    //     _revokeDepositAccessControl(_depositLimit);
    // }

    /// @notice The ```pauseRepay``` function pauses repay functionality
    /// @param _isPaused The new pause state
    function pauseRepay(bool _isPaused) external {
        _requireProtocolOrOwner();
        if (isRepayAccessControlRevoked) revert AccessControlRevoked();
        _pauseRepay(_isPaused);
    }

    /// @notice The ```revokeRepayAccessControl``` function revokes repay access control
    function revokeRepayAccessControl() external {
        _requireProtocolOrOwner();
        _revokeRepayAccessControl();
    }

    /// @notice The ```pauseWithdraw``` function pauses withdraw functionality
    /// @param _isPaused The new pause state
    function pauseWithdraw(bool _isPaused) external {
        _requireProtocolOrOwner();
        if (isWithdrawAccessControlRevoked) revert AccessControlRevoked();
        _pauseWithdraw(_isPaused);
    }

    /// @notice The ```revokeWithdrawAccessControl``` function revokes withdraw access control
    function revokeWithdrawAccessControl() external {
        _requireProtocolOrOwner();
        _revokeWithdrawAccessControl();
    }

    /// @notice The ```pauseLiquidate``` function pauses liquidate functionality
    /// @param _isPaused The new pause state
    function pauseLiquidate(bool _isPaused) external {
        _requireProtocolOrOwner();
        if (isLiquidateAccessControlRevoked) revert AccessControlRevoked();
        _pauseLiquidate(_isPaused);
    }

    /// @notice The ```revokeLiquidateAccessControl``` function revokes liquidate access control
    function revokeLiquidateAccessControl() external {
        _requireProtocolOrOwner();
        _revokeLiquidateAccessControl();
    }

    /// @notice The ```pauseInterest``` function pauses interest functionality
    /// @param _isPaused The new pause state
    function pauseInterest(bool _isPaused) external {
        _requireProtocolOrOwner();
        if (isInterestAccessControlRevoked) revert AccessControlRevoked();
        // Resets the lastTimestamp which has the effect of no interest accruing over the pause period
        _addInterest();
        _pauseInterest(_isPaused);
    }

    /// @notice The ```revokeInterestAccessControl``` function revokes interest access control
    function revokeInterestAccessControl() external {
        _requireProtocolOrOwner();
        _revokeInterestAccessControl();
    }
}
