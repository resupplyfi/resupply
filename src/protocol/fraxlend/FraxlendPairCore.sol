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
// ========================= FraxlendPairCore =========================
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

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FraxlendPairAccessControl } from "./FraxlendPairAccessControl.sol";
import { FraxlendPairConstants } from "./FraxlendPairConstants.sol";
import { VaultAccount, VaultAccountingLibrary } from "../../libraries/VaultAccount.sol";
import { SafeERC20 } from "../../libraries/SafeERC20.sol";
import { IDualOracle } from "../../interfaces/IDualOracle.sol";
import { IRateCalculatorV2 } from "../../interfaces/IRateCalculatorV2.sol";
import { ISwapper } from "../../interfaces/ISwapper.sol";

/// @title FraxlendPairCore
/// @author Drake Evans (Frax Finance) https://github.com/drakeevans
/// @notice  An abstract contract which contains the core logic and storage for the FraxlendPair
abstract contract FraxlendPairCore is FraxlendPairAccessControl, FraxlendPairConstants, ReentrancyGuard {
    using VaultAccountingLibrary for VaultAccount;
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    function version() external pure returns (uint256 _major, uint256 _minor, uint256 _patch) {
        _major = 3;
        _minor = 0;
        _patch = 0;
    }

    // ============================================================================================
    // Settings set by constructor()
    // ============================================================================================

    // Asset and collateral contracts
    IERC20 internal immutable assetContract;
    IERC20 public immutable collateralContract;

    // LTV Settings
    /// @notice The maximum LTV allowed for this pair
    /// @dev 1e5 precision
    uint256 public maxLTV;

    // Liquidation Fees
    /// @notice The liquidation fee, given as a % of repayment amount
    /// @dev 1e5 precision
    uint256 public liquidationFee;


    // Interest Rate Calculator Contract
    IRateCalculatorV2 public rateContract; // For complex rate calculations

    // Swapper
    mapping(address => bool) public swappers; // approved swapper addresses

    // Metadata
    string public name;
    

    // ============================================================================================
    // Storage
    // ============================================================================================

    /// @notice Stores information about the current interest rate
    /// @dev struct is packed to reduce SLOADs. feeToProtocolRate is 1e5 precision, ratePerSec & fullUtilizationRate is 1e18 precision
    CurrentRateInfo public currentRateInfo;

    struct CurrentRateInfo {
        uint32 lastBlock;
        uint32 feeToProtocolRate; // Fee amount 1e5 precision
        uint64 lastTimestamp;
        uint64 ratePerSec;
        uint64 fullUtilizationRate;
    }

    /// @notice Stores information about the current exchange rate. Collateral:Asset ratio
    /// @dev Struct packed to save SLOADs. Amount of Collateral Token to buy 1e18 Asset Token
    ExchangeRateInfo public exchangeRateInfo;

    struct ExchangeRateInfo {
        address oracle;
        uint32 maxOracleDeviation; // % of larger number, 1e5 precision
        uint184 lastTimestamp;
        uint256 lowExchangeRate;
        uint256 highExchangeRate;
    }

    // Contract Level Accounting
    VaultAccount public totalBorrow; // amount = total borrow amount with interest accrued, shares = total shares outstanding
    uint256 public totalCollateral; // total amount of collateral in contract
    uint256 public claimableFees; //amount of interest gained that is claimable as fees

    // User Level Accounting
    /// @notice Stores the balance of collateral for each user
    mapping(address => uint256) public userCollateralBalance; // amount of collateral each user is backed
    /// @notice Stores the balance of borrow shares for each user
    mapping(address => uint256) public userBorrowShares; // represents the shares held by individuals

    // NOTE: user shares of assets are represented as ERC-20 tokens and accessible via balanceOf()

    // ============================================================================================
    // Constructor
    // ============================================================================================

    /// @notice The ```constructor``` function is called on deployment
    /// @param _configData abi.encode(address _asset, address _collateral, address _oracle, uint32 _maxOracleDeviation, address _rateContract, uint64 _fullUtilizationRate, uint256 _maxLTV, uint256 _cleanLiquidationFee, uint256 _dirtyLiquidationFee, uint256 _protocolLiquidationFee)
    /// @param _immutables abi.encode(address _circuitBreakerAddress, address _comptrollerAddress, address _timelockAddress)
    /// @param _customConfigData abi.encode(string memory _nameOfContract, string memory _symbolOfContract, uint8 _decimalsOfContract)
    constructor(
        bytes memory _configData,
        bytes memory _immutables,
        bytes memory _customConfigData
    ) FraxlendPairAccessControl(_immutables) {
        {
            (
                address _asset,
                address _collateral,
                address _oracle,
                uint32 _maxOracleDeviation,
                address _rateContract,
                uint64 _fullUtilizationRate,
                uint256 _maxLTV,
                uint256 _liquidationFee
            ) = abi.decode(
                    _configData,
                    (address, address, address, uint32, address, uint64, uint256, uint256)
                );

            // Pair Settings
            assetContract = IERC20(_asset);
            collateralContract = IERC20(_collateral);

            currentRateInfo.feeToProtocolRate = 0;
            currentRateInfo.fullUtilizationRate = _fullUtilizationRate;
            currentRateInfo.lastTimestamp = uint64(block.timestamp - 1);
            currentRateInfo.lastBlock = uint32(block.number - 1);

            exchangeRateInfo.oracle = _oracle;
            exchangeRateInfo.maxOracleDeviation = _maxOracleDeviation;

            rateContract = IRateCalculatorV2(_rateContract);

            //Liquidation Fee Settings
            liquidationFee = _liquidationFee;

            // set maxLTV
            maxLTV = _maxLTV;
        }

        {
            (string memory _name) = abi.decode(
                _customConfigData,
                (string)
            );

            // Metadata
            name = _name;

            // Instantiate Interest
            _addInterest();
            // Instantiate Exchange Rate
            _updateExchangeRate();
        }
    }

    // ============================================================================================
    // Internal Helpers
    // ============================================================================================

    /// @notice The ```totalAssetAvailable``` function returns the total balance of Asset Tokens in the contract
    /// @return The balance of Asset Tokens held by contract
    function totalAssetAvailable(
    ) public view returns (uint256) {
        // return _totalAsset.amount - _totalBorrow.amount;

        //TODO maybe include an outside call to do other checks if minting is available.
        //     ex on L2 there may not be enough stables bridged to borrow even if borrow limit not reached
        return borrowLimit - totalBorrow.amount;
    }

    /// @notice The ```_isSolvent``` function determines if a given borrower is solvent given an exchange rate
    /// @param _borrower The borrower address to check
    /// @param _exchangeRate The exchange rate, i.e. the amount of collateral to buy 1e18 asset
    /// @return Whether borrower is solvent
    function _isSolvent(address _borrower, uint256 _exchangeRate) internal view returns (bool) {
        if (maxLTV == 0) return true;
        uint256 _borrowerAmount = totalBorrow.toAmount(userBorrowShares[_borrower], true);
        if (_borrowerAmount == 0) return true;
        uint256 _collateralAmount = userCollateralBalance[_borrower];
        if (_collateralAmount == 0) return false;

        uint256 _ltv = (((_borrowerAmount * _exchangeRate) / EXCHANGE_PRECISION) * LTV_PRECISION) / _collateralAmount;
        return _ltv <= maxLTV;
    }

    // ============================================================================================
    // Modifiers
    // ============================================================================================

    /// @notice Checks for solvency AFTER executing contract code
    /// @param _borrower The borrower whose solvency we will check
    modifier isSolvent(address _borrower) {
        _;
        ExchangeRateInfo memory _exchangeRateInfo = exchangeRateInfo;

        if (!_isSolvent(_borrower, exchangeRateInfo.highExchangeRate)) {
            revert Insolvent(
                totalBorrow.toAmount(userBorrowShares[_borrower], true),
                userCollateralBalance[_borrower],
                exchangeRateInfo.highExchangeRate
            );
        }
    }

    // ============================================================================================
    // Functions: Interest Accumulation and Adjustment
    // ============================================================================================

    /// @notice The ```AddInterest``` event is emitted when interest is accrued by borrowers
    /// @param interestEarned The total interest accrued by all borrowers
    /// @param rate The interest rate used to calculate accrued interest
    event AddInterest(uint256 interestEarned, uint256 rate);

    /// @notice The ```UpdateRate``` event is emitted when the interest rate is updated
    /// @param oldRatePerSec The old interest rate (per second)
    /// @param oldFullUtilizationRate The old full utilization rate
    /// @param newRatePerSec The new interest rate (per second)
    /// @param newFullUtilizationRate The new full utilization rate
    event UpdateRate(
        uint256 oldRatePerSec,
        uint256 oldFullUtilizationRate,
        uint256 newRatePerSec,
        uint256 newFullUtilizationRate
    );

    /// @notice The ```addInterest``` function is a public implementation of _addInterest and allows 3rd parties to trigger interest accrual
    /// @return _interestEarned The amount of interest accrued by all borrowers
    /// @return _currentRateInfo The new rate info struct
    /// @return _claimableFees The new total of fees that are claimable
    /// @return _totalBorrow The new total borrow struct
    function addInterest(
        bool _returnAccounting
    )
        external
        nonReentrant
        returns (
            uint256 _interestEarned,
            CurrentRateInfo memory _currentRateInfo,
            uint256 _claimableFees,
            VaultAccount memory _totalBorrow
        )
    {
        (, _interestEarned, _currentRateInfo) = _addInterest();
        if (_returnAccounting) {
            _claimableFees = claimableFees;
            _totalBorrow = totalBorrow;
        }
    }

    /// @notice The ```previewAddInterest``` function
    /// @return _interestEarned The amount of interest accrued by all borrowers
    /// @return _newCurrentRateInfo The new rate info struct
    /// @return _claimableFees The new total of fees that are claimable
    /// @return _totalBorrow The new total borrow struct
    function previewAddInterest()
        public
        view
        returns (
            uint256 _interestEarned,
            CurrentRateInfo memory _newCurrentRateInfo,
            uint256 _claimableFees,
            VaultAccount memory _totalBorrow
        )
    {
        _newCurrentRateInfo = currentRateInfo;
        // Write return values
        InterestCalculationResults memory _results = _calculateInterest(_newCurrentRateInfo);

        if (_results.isInterestUpdated) {
            _interestEarned = _results.interestEarned;

            _newCurrentRateInfo.ratePerSec = _results.newRate;
            _newCurrentRateInfo.fullUtilizationRate = _results.newFullUtilizationRate;

            _claimableFees = claimableFees + uint128(_interestEarned);
            _totalBorrow = _results.totalBorrow;
        } else {
            _claimableFees = claimableFees;
            _totalBorrow = totalBorrow;
        }
    }

    struct InterestCalculationResults {
        bool isInterestUpdated;
        uint64 newRate;
        uint64 newFullUtilizationRate;
        uint256 interestEarned;
        VaultAccount totalBorrow;
    }

    /// @notice The ```_calculateInterest``` function calculates the interest to be accrued and the new interest rate info
    /// @param _currentRateInfo The current rate info
    /// @return _results The results of the interest calculation
    function _calculateInterest(
        CurrentRateInfo memory _currentRateInfo
    ) internal view returns (InterestCalculationResults memory _results) {
        // Short circuit if interest already calculated this block OR if interest is paused
        if (_currentRateInfo.lastTimestamp != block.timestamp && !isInterestPaused) {
            // Indicate that interest is updated and calculated
            _results.isInterestUpdated = true;

            // Write return values and use these to save gas
            _results.totalBorrow = totalBorrow;

            // Time elapsed since last interest update
            uint256 _deltaTime = block.timestamp - _currentRateInfo.lastTimestamp;

            // Get the utilization rate
            uint256 _utilizationRate = borrowLimit == 0
                ? 0
                : (UTIL_PREC * _results.totalBorrow.amount) / borrowLimit;

            // Request new interest rate and full utilization rate from the rate calculator
            (_results.newRate, _results.newFullUtilizationRate) = IRateCalculatorV2(rateContract).getNewRate(
                _deltaTime,
                _utilizationRate,
                _currentRateInfo.fullUtilizationRate
            );

            // Calculate interest accrued
            _results.interestEarned = (_deltaTime * _results.totalBorrow.amount * _results.newRate) / RATE_PRECISION;

            // Accrue interest (if any) and fees iff no overflow
            if (
                _results.interestEarned > 0 &&
                _results.interestEarned + _results.totalBorrow.amount <= type(uint128).max &&
                _results.interestEarned + borrowLimit <= type(uint128).max
            ) {
                // Increment totalBorrow by interestEarned
                _results.totalBorrow.amount += uint128(_results.interestEarned);
            }
        }
    }

    /// @notice The ```_addInterest``` function is invoked prior to every external function and is used to accrue interest and update interest rate
    /// @dev Can only called once per block
    /// @return _isInterestUpdated True if interest was calculated
    /// @return _interestEarned The amount of interest accrued by all borrowers
    /// @return _currentRateInfo The new rate info struct
    function _addInterest()
        internal
        returns (
            bool _isInterestUpdated,
            uint256 _interestEarned,
            CurrentRateInfo memory _currentRateInfo
        )
    {
        // Pull from storage and set default return values
        _currentRateInfo = currentRateInfo;

        // Calc interest
        InterestCalculationResults memory _results = _calculateInterest(_currentRateInfo);

        // Write return values only if interest was updated and calculated
        if (_results.isInterestUpdated) {
            _isInterestUpdated = _results.isInterestUpdated;
            _interestEarned = _results.interestEarned;

            // emit here so that we have access to the old values
            emit UpdateRate(
                _currentRateInfo.ratePerSec,
                _currentRateInfo.fullUtilizationRate,
                _results.newRate,
                _results.newFullUtilizationRate
            );
            emit AddInterest(_interestEarned, _results.newRate);

            // overwrite original values
            _currentRateInfo.ratePerSec = _results.newRate;
            _currentRateInfo.fullUtilizationRate = _results.newFullUtilizationRate;
            _currentRateInfo.lastTimestamp = uint64(block.timestamp);
            _currentRateInfo.lastBlock = uint32(block.number);

            // Effects: write to state
            currentRateInfo = _currentRateInfo;
            claimableFees += _interestEarned; //increase claimable fees by interest earned
            totalBorrow = _results.totalBorrow;
        }
    }

    // ============================================================================================
    // Functions: ExchangeRate
    // ============================================================================================

    /// @notice The ```UpdateExchangeRate``` event is emitted when the Collateral:Asset exchange rate is updated
    /// @param lowExchangeRate The low exchange rate
    /// @param highExchangeRate The high exchange rate
    event UpdateExchangeRate(uint256 lowExchangeRate, uint256 highExchangeRate);

    /// @notice The ```WarnOracleData``` event is emitted when one of the oracles has stale or otherwise problematic data
    /// @param oracle The oracle address
    event WarnOracleData(address oracle);

    /// @notice The ```updateExchangeRate``` function is the external implementation of _updateExchangeRate.
    /// @dev This function is invoked at most once per block as these queries can be expensive
    /// @return _isBorrowAllowed True if deviation is within bounds
    /// @return _lowExchangeRate The low exchange rate
    /// @return _highExchangeRate The high exchange rate
    function updateExchangeRate()
        external
        nonReentrant
        returns (bool _isBorrowAllowed, uint256 _lowExchangeRate, uint256 _highExchangeRate)
    {
        return _updateExchangeRate();
    }

    /// @notice The ```_updateExchangeRate``` function retrieves the latest exchange rate. i.e how much collateral to buy 1e18 asset.
    /// @dev This function is invoked at most once per block as these queries can be expensive
    /// @return _isBorrowAllowed True if deviation is within bounds
    /// @return _lowExchangeRate The low exchange rate
    /// @return _highExchangeRate The high exchange rate

    function _updateExchangeRate()
        internal
        returns (bool _isBorrowAllowed, uint256 _lowExchangeRate, uint256 _highExchangeRate)
    {
        // Pull from storage to save gas and set default return values
        ExchangeRateInfo memory _exchangeRateInfo = exchangeRateInfo;

        // Short circuit if already updated this block
        if (_exchangeRateInfo.lastTimestamp != block.timestamp) {
            // Get the latest exchange rate from the dual oracle
            bool _oneOracleBad;
            (_oneOracleBad, _lowExchangeRate, _highExchangeRate) = IDualOracle(_exchangeRateInfo.oracle).getPrices();

            // If one oracle is bad data, emit an event for off-chain monitoring
            if (_oneOracleBad) emit WarnOracleData(_exchangeRateInfo.oracle);

            // Effects: Bookkeeping and write to storage
            _exchangeRateInfo.lastTimestamp = uint184(block.timestamp);
            _exchangeRateInfo.lowExchangeRate = _lowExchangeRate;
            _exchangeRateInfo.highExchangeRate = _highExchangeRate;
            exchangeRateInfo = _exchangeRateInfo;
            emit UpdateExchangeRate(_lowExchangeRate, _highExchangeRate);
        } else {
            // Use default return values if already updated this block
            _lowExchangeRate = _exchangeRateInfo.lowExchangeRate;
            _highExchangeRate = _exchangeRateInfo.highExchangeRate;
        }

        uint256 _deviation = (DEVIATION_PRECISION *
            (_exchangeRateInfo.highExchangeRate - _exchangeRateInfo.lowExchangeRate)) /
            _exchangeRateInfo.highExchangeRate;
        if (_deviation <= _exchangeRateInfo.maxOracleDeviation) {
            _isBorrowAllowed = true;
        }
    }

    // ============================================================================================
    // Functions: Lending
    // ============================================================================================

    // ONLY Protocol can lend

    // ============================================================================================
    // Functions: Borrowing
    // ============================================================================================

    /// @notice The ```BorrowAsset``` event is emitted when a borrower increases their position
    /// @param _borrower The borrower whose account was debited
    /// @param _receiver The address to which the Asset Tokens were transferred
    /// @param _borrowAmount The amount of Asset Tokens transferred
    /// @param _sharesAdded The number of Borrow Shares the borrower was debited
    event BorrowAsset(
        address indexed _borrower,
        address indexed _receiver,
        uint256 _borrowAmount,
        uint256 _sharesAdded
    );

    /// @notice The ```_borrowAsset``` function is the internal implementation for borrowing assets
    /// @param _borrowAmount The amount of the Asset Token to borrow
    /// @param _receiver The address to receive the Asset Tokens
    /// @return _sharesAdded The amount of borrow shares the msg.sender will be debited
    function _borrowAsset(uint128 _borrowAmount, address _receiver) internal returns (uint256 _sharesAdded) {
        // Get borrow accounting from storage to save gas
        VaultAccount memory _totalBorrow = totalBorrow;

        // Check available capital (not strictly necessary because balance will underflow, but better revert message)
        uint256 _assetsAvailable = totalAssetAvailable();
        if (_assetsAvailable < _borrowAmount) {
            revert InsufficientAssetsInContract(_assetsAvailable, _borrowAmount);
        }

        // Calculate the number of shares to add based on the amount to borrow
        _sharesAdded = _totalBorrow.toShares(_borrowAmount, true);

        // Effects: Bookkeeping to add shares & amounts to total Borrow accounting
        _totalBorrow.amount += _borrowAmount;
        _totalBorrow.shares += uint128(_sharesAdded);
        // NOTE: we can safely cast here because shares are always less than amount and _borrowAmount is uint128

        // Effects: write back to storage
        totalBorrow = _totalBorrow;
        userBorrowShares[msg.sender] += _sharesAdded;

        // Interactions
        if (_receiver != address(this)) {
            assetContract.safeTransfer(_receiver, _borrowAmount);
        }
        emit BorrowAsset(msg.sender, _receiver, _borrowAmount, _sharesAdded);
    }

    /// @notice The ```borrowAsset``` function allows a user to open/increase a borrow position
    /// @dev Borrower must call ```ERC20.approve``` on the Collateral Token contract if applicable
    /// @param _borrowAmount The amount of Asset Token to borrow
    /// @param _collateralAmount The amount of Collateral Token to transfer to Pair
    /// @param _receiver The address which will receive the Asset Tokens
    /// @return _shares The number of borrow Shares the msg.sender will be debited
    function borrowAsset(
        uint256 _borrowAmount,
        uint256 _collateralAmount,
        address _receiver
    ) external nonReentrant isSolvent(msg.sender) returns (uint256 _shares) {
        if (_receiver == address(0)) revert InvalidReceiver();

        // Accrue interest if necessary
        _addInterest();

        // Check if borrow will violate the borrow limit and revert if necessary
        if (borrowLimit < totalBorrow.amount + _borrowAmount) revert ExceedsBorrowLimit();

        // Update _exchangeRate and check if borrow is allowed based on deviation
        (bool _isBorrowAllowed, , ) = _updateExchangeRate();
        if (!_isBorrowAllowed) revert ExceedsMaxOracleDeviation();

        // Only add collateral if necessary
        if (_collateralAmount > 0) {
            _addCollateral(msg.sender, _collateralAmount, msg.sender);
        }

        // Effects: Call internal borrow function
        _shares = _borrowAsset(_borrowAmount.toUint128(), _receiver);
    }

    /// @notice The ```AddCollateral``` event is emitted when a borrower adds collateral to their position
    /// @param sender The source of funds for the new collateral
    /// @param borrower The borrower account for which the collateral should be credited
    /// @param collateralAmount The amount of Collateral Token to be transferred
    event AddCollateral(address indexed sender, address indexed borrower, uint256 collateralAmount);

    /// @notice The ```_addCollateral``` function is an internal implementation for adding collateral to a borrowers position
    /// @param _sender The source of funds for the new collateral
    /// @param _collateralAmount The amount of Collateral Token to be transferred
    /// @param _borrower The borrower account for which the collateral should be credited
    function _addCollateral(address _sender, uint256 _collateralAmount, address _borrower) internal {
        // Effects: write to state
        userCollateralBalance[_borrower] += _collateralAmount;
        totalCollateral += _collateralAmount;

        // Interactions
        if (_sender != address(this)) {
            collateralContract.safeTransferFrom(_sender, address(this), _collateralAmount);
        }
        emit AddCollateral(_sender, _borrower, _collateralAmount);
    }

    /// @notice The ```addCollateral``` function allows the caller to add Collateral Token to a borrowers position
    /// @dev msg.sender must call ERC20.approve() on the Collateral Token contract prior to invocation
    /// @param _collateralAmount The amount of Collateral Token to be added to borrower's position
    /// @param _borrower The account to be credited
    function addCollateral(uint256 _collateralAmount, address _borrower) external nonReentrant {
        if (_borrower == address(0)) revert InvalidReceiver();

        _addInterest();
        _addCollateral(msg.sender, _collateralAmount, _borrower);
    }

    /// @notice The ```RemoveCollateral``` event is emitted when collateral is removed from a borrower's position
    /// @param _sender The account from which funds are transferred
    /// @param _collateralAmount The amount of Collateral Token to be transferred
    /// @param _receiver The address to which Collateral Tokens will be transferred
    event RemoveCollateral(
        address indexed _sender,
        uint256 _collateralAmount,
        address indexed _receiver,
        address indexed _borrower
    );

    /// @notice The ```_removeCollateral``` function is the internal implementation for removing collateral from a borrower's position
    /// @param _collateralAmount The amount of Collateral Token to remove from the borrower's position
    /// @param _receiver The address to receive the Collateral Token transferred
    /// @param _borrower The borrower whose account will be debited the Collateral amount
    function _removeCollateral(uint256 _collateralAmount, address _receiver, address _borrower) internal {
        // Effects: write to state
        // NOTE: Following line will revert on underflow if _collateralAmount > userCollateralBalance
        userCollateralBalance[_borrower] -= _collateralAmount;
        // NOTE: Following line will revert on underflow if totalCollateral < _collateralAmount
        totalCollateral -= _collateralAmount;

        // Interactions
        if (_receiver != address(this)) {
            collateralContract.safeTransfer(_receiver, _collateralAmount);
        }
        emit RemoveCollateral(msg.sender, _collateralAmount, _receiver, _borrower);
    }

    /// @notice The ```removeCollateral``` function is used to remove collateral from msg.sender's borrow position
    /// @dev msg.sender must be solvent after invocation or transaction will revert
    /// @param _collateralAmount The amount of Collateral Token to transfer
    /// @param _receiver The address to receive the transferred funds
    function removeCollateral(
        uint256 _collateralAmount,
        address _receiver
    ) external nonReentrant isSolvent(msg.sender) {
        if (_receiver == address(0)) revert InvalidReceiver();

        _addInterest();
        // Note: exchange rate is irrelevant when borrower has no debt shares
        if (userBorrowShares[msg.sender] > 0) {
            (bool _isBorrowAllowed, , ) = _updateExchangeRate();
            if (!_isBorrowAllowed) revert ExceedsMaxOracleDeviation();
        }
        _removeCollateral(_collateralAmount, _receiver, msg.sender);
    }

    /// @notice The ```RepayAsset``` event is emitted whenever a debt position is repaid
    /// @param payer The address paying for the repayment
    /// @param borrower The borrower whose account will be credited
    /// @param amountToRepay The amount of Asset token to be transferred
    /// @param shares The amount of Borrow Shares which will be debited from the borrower after repayment
    event RepayAsset(address indexed payer, address indexed borrower, uint256 amountToRepay, uint256 shares);

    /// @notice The ```_repayAsset``` function is the internal implementation for repaying a borrow position
    /// @dev The payer must have called ERC20.approve() on the Asset Token contract prior to invocation
    /// @param _totalBorrow An in memory copy of the totalBorrow VaultAccount struct
    /// @param _amountToRepay The amount of Asset Token to transfer
    /// @param _shares The number of Borrow Shares the sender is repaying
    /// @param _payer The address from which funds will be transferred
    /// @param _borrower The borrower account which will be credited
    function _repayAsset(
        VaultAccount memory _totalBorrow,
        uint128 _amountToRepay,
        uint128 _shares,
        address _payer,
        address _borrower
    ) internal {
        // Effects: Bookkeeping
        _totalBorrow.amount -= _amountToRepay;
        _totalBorrow.shares -= _shares;

        // Effects: write to state
        userBorrowShares[_borrower] -= _shares;
        totalBorrow = _totalBorrow;

        // Interactions
        if (_payer != address(this)) {
            assetContract.safeTransferFrom(_payer, address(this), _amountToRepay);
        }
        emit RepayAsset(_payer, _borrower, _amountToRepay, _shares);
    }

    /// @notice The ```repayAsset``` function allows the caller to pay down the debt for a given borrower.
    /// @dev Caller must first invoke ```ERC20.approve()``` for the Asset Token contract
    /// @param _shares The number of Borrow Shares which will be repaid by the call
    /// @param _borrower The account for which the debt will be reduced
    /// @return _amountToRepay The amount of Asset Tokens which were transferred in order to repay the Borrow Shares
    function repayAsset(uint256 _shares, address _borrower) external nonReentrant returns (uint256 _amountToRepay) {
        if (_borrower == address(0)) revert InvalidReceiver();

        // Check if repay is paused revert if necessary
        if (isRepayPaused) revert RepayPaused();

        // Accrue interest if necessary
        _addInterest();

        // Calculate amount to repay based on shares
        VaultAccount memory _totalBorrow = totalBorrow;
        _amountToRepay = _totalBorrow.toAmount(_shares, true);

        // Execute repayment effects
        _repayAsset(_totalBorrow, _amountToRepay.toUint128(), _shares.toUint128(), msg.sender, _borrower);
    }

    // ============================================================================================
    // Functions: Liquidations
    // ============================================================================================
    /// @notice The ```Liquidate``` event is emitted when a liquidation occurs
    /// @param _borrower The borrower account for which the liquidation occurred
    /// @param _collateralForLiquidator The amount of Collateral Token transferred to the liquidator
    event Liquidate(
        address indexed _borrower,
        uint256 _collateralForLiquidator,
        uint256 _sharesLiquidated,
        uint256 _amountLiquidatorToRepay,
        uint256 _feesAmount
        // uint256 _sharesToAdjust,
        // uint256 _amountToAdjust
    );

    /// @notice The ```liquidate``` function allows a third party to repay a borrower's debt if they have become insolvent
    /// @dev Caller must invoke ```ERC20.approve``` on the Asset Token contract prior to calling ```Liquidate()```
    /// @param _borrower The account for which the repayment is credited and from whom collateral will be taken
    /// @return _collateralForLiquidator The amount of Collateral Token transferred to the liquidator
    function liquidate(
        // uint128 _sharesToLiquidate,
        // uint256 _deadline,
        address _borrower
    ) external nonReentrant returns (uint256 _collateralForLiquidator) {
        if (_borrower == address(0)) revert InvalidReceiver();

        // Check if liquidate is paused revert if necessary
        if (isLiquidatePaused) revert LiquidatePaused();

        // Ensure deadline has not passed
        // if (block.timestamp > _deadline) revert PastDeadline(block.timestamp, _deadline);

        // accrue interest if necessary
        _addInterest();

        // Update exchange rate and use the lower rate for liquidations
        (, uint256 _exchangeRate, ) = _updateExchangeRate();

        // Check if borrower is solvent, revert if they are
        if (_isSolvent(_borrower, _exchangeRate)) {
            revert BorrowerSolvent();
        }

        // Read from state
        VaultAccount memory _totalBorrow = totalBorrow;
        uint256 _userCollateralBalance = userCollateralBalance[_borrower];
        uint128 _borrowerShares = userBorrowShares[_borrower].toUint128();

        // Prevent stack-too-deep
        int256 _leftoverCollateral;
        uint256 _feesAmount;
        {
            // Checks & Calculations
            // Determine the liquidation amount in collateral units (i.e. how much debt liquidator is going to repay)
            uint256 _liquidationAmountInCollateralUnits = ((_totalBorrow.toAmount(_borrowerShares, false) *
                _exchangeRate) / EXCHANGE_PRECISION);

            // We first optimistically calculate the amount of collateral to give the liquidator based on the higher clean liquidation fee
            // This fee only applies if the liquidator does a full liquidation
            uint256 _optimisticCollateralForLiquidator = (_liquidationAmountInCollateralUnits *
                (LIQ_PRECISION + liquidationFee)) / LIQ_PRECISION;

            // Because interest accrues every block, _liquidationAmountInCollateralUnits from a few lines up is an ever increasing value
            // This means that leftoverCollateral can occasionally go negative by a few hundred wei (cleanLiqFee premium covers this for liquidator)
            _leftoverCollateral = (_userCollateralBalance.toInt256() - _optimisticCollateralForLiquidator.toInt256());

            // If cleanLiquidation fee results in no leftover collateral, give liquidator all the collateral
            // This will only be true when there liquidator is cleaning out the position
            //edit: just clamp to user
            _collateralForLiquidator = _leftoverCollateral <= 0
                ? _userCollateralBalance
                : _collateralForLiquidator;
        }

        // Calculated here for use during repayment, grouped with other calcs before effects start
        uint128 _amountLiquidatorToRepay = (_totalBorrow.toAmount(_borrowerShares, true)).toUint128();

        emit Liquidate(
                _borrower,
                _collateralForLiquidator,
                _borrowerShares,
                _amountLiquidatorToRepay,
                _feesAmount
            );

        // Effects & Interactions
        // NOTE: reverts if _shares > userBorrowShares
        _repayAsset(
            _totalBorrow,
            _amountLiquidatorToRepay,
            _borrowerShares,
            msg.sender,
            _borrower
        ); // liquidator repays shares on behalf of borrower
        // NOTE: reverts if _collateralForLiquidator > userCollateralBalance
        // Collateral is removed on behalf of borrower and sent to liquidator
        // NOTE: reverts if _collateralForLiquidator > userCollateralBalance
        _removeCollateral(_collateralForLiquidator, msg.sender, _borrower);
        // Adjust bookkeeping only (decreases collateral held by borrower)
        _removeCollateral(_feesAmount, address(this), _borrower);
        // Adjusts bookkeeping only (increases collateral held by protocol)
        _addCollateral(address(this), _feesAmount, address(this));
    }

    // ============================================================================================
    // Functions: Leverage
    // ============================================================================================

    /// @notice The ```LeveragedPosition``` event is emitted when a borrower takes out a new leveraged position
    /// @param _borrower The account for which the debt is debited
    /// @param _swapperAddress The address of the swapper which conforms the FraxSwap interface
    /// @param _borrowAmount The amount of Asset Token to be borrowed to be borrowed
    /// @param _borrowShares The number of Borrow Shares the borrower is credited
    /// @param _initialCollateralAmount The amount of initial Collateral Tokens supplied by the borrower
    /// @param _amountCollateralOut The amount of Collateral Token which was received for the Asset Tokens
    event LeveragedPosition(
        address indexed _borrower,
        address _swapperAddress,
        uint256 _borrowAmount,
        uint256 _borrowShares,
        uint256 _initialCollateralAmount,
        uint256 _amountCollateralOut
    );

    /// @notice The ```leveragedPosition``` function allows a user to enter a leveraged borrow position with minimal upfront Collateral
    /// @dev Caller must invoke ```ERC20.approve()``` on the Collateral Token contract prior to calling function
    /// @param _swapperAddress The address of the whitelisted swapper to use to swap borrowed Asset Tokens for Collateral Tokens
    /// @param _borrowAmount The amount of Asset Tokens borrowed
    /// @param _initialCollateralAmount The initial amount of Collateral Tokens supplied by the borrower
    /// @param _amountCollateralOutMin The minimum amount of Collateral Tokens to be received in exchange for the borrowed Asset Tokens
    /// @param _path An array containing the addresses of ERC20 tokens to swap.  Adheres to UniV2 style path params.
    /// @return _totalCollateralBalance The total amount of Collateral Tokens added to a users account (initial + swap)
    function leveragedPosition(
        address _swapperAddress,
        uint256 _borrowAmount,
        uint256 _initialCollateralAmount,
        uint256 _amountCollateralOutMin,
        address[] memory _path
    ) external nonReentrant isSolvent(msg.sender) returns (uint256 _totalCollateralBalance) {
        // Accrue interest if necessary
        _addInterest();

        // Update exchange rate and check if borrow is allowed, revert if not
        {
            (bool _isBorrowAllowed, , ) = _updateExchangeRate();
            if (!_isBorrowAllowed) revert ExceedsMaxOracleDeviation();
        }

        IERC20 _assetContract = assetContract;
        IERC20 _collateralContract = collateralContract;

        if (!swappers[_swapperAddress]) {
            revert BadSwapper();
        }
        if (_path[0] != address(_assetContract)) {
            revert InvalidPath(address(_assetContract), _path[0]);
        }
        if (_path[_path.length - 1] != address(_collateralContract)) {
            revert InvalidPath(address(_collateralContract), _path[_path.length - 1]);
        }

        // Add initial collateral
        if (_initialCollateralAmount > 0) {
            _addCollateral(msg.sender, _initialCollateralAmount, msg.sender);
        }

        // Debit borrowers account
        // setting recipient to address(this) means no transfer will happen
        uint256 _borrowShares = _borrowAsset(_borrowAmount.toUint128(), address(this));

        // Interactions
        _assetContract.approve(_swapperAddress, _borrowAmount);

        // Even though swappers are trusted, we verify the balance before and after swap
        uint256 _initialCollateralBalance = _collateralContract.balanceOf(address(this));
        ISwapper(_swapperAddress).swapExactTokensForTokens(
            _borrowAmount,
            _amountCollateralOutMin,
            _path,
            address(this),
            block.timestamp
        );
        uint256 _finalCollateralBalance = _collateralContract.balanceOf(address(this));

        // Note: VIOLATES CHECKS-EFFECTS-INTERACTION pattern, make sure function is NONREENTRANT
        // Effects: bookkeeping & write to state
        uint256 _amountCollateralOut = _finalCollateralBalance - _initialCollateralBalance;
        if (_amountCollateralOut < _amountCollateralOutMin) {
            revert SlippageTooHigh(_amountCollateralOutMin, _amountCollateralOut);
        }

        // address(this) as _sender means no transfer occurs as the pair has already received the collateral during swap
        _addCollateral(address(this), _amountCollateralOut, msg.sender);

        _totalCollateralBalance = _initialCollateralAmount + _amountCollateralOut;
        emit LeveragedPosition(
            msg.sender,
            _swapperAddress,
            _borrowAmount,
            _borrowShares,
            _initialCollateralAmount,
            _amountCollateralOut
        );
    }

    /// @notice The ```RepayAssetWithCollateral``` event is emitted whenever ```repayAssetWithCollateral()``` is invoked
    /// @param _borrower The borrower account for which the repayment is taking place
    /// @param _swapperAddress The address of the whitelisted swapper to use for token swaps
    /// @param _collateralToSwap The amount of Collateral Token to swap and use for repayment
    /// @param _amountAssetOut The amount of Asset Token which was repaid
    /// @param _sharesRepaid The number of Borrow Shares which were repaid
    event RepayAssetWithCollateral(
        address indexed _borrower,
        address _swapperAddress,
        uint256 _collateralToSwap,
        uint256 _amountAssetOut,
        uint256 _sharesRepaid
    );

    /// @notice The ```repayAssetWithCollateral``` function allows a borrower to repay their debt using existing collateral in contract
    /// @param _swapperAddress The address of the whitelisted swapper to use for token swaps
    /// @param _collateralToSwap The amount of Collateral Tokens to swap for Asset Tokens
    /// @param _amountAssetOutMin The minimum amount of Asset Tokens to receive during the swap
    /// @param _path An array containing the addresses of ERC20 tokens to swap.  Adheres to UniV2 style path params.
    /// @return _amountAssetOut The amount of Asset Tokens received for the Collateral Tokens, the amount the borrowers account was credited
    function repayAssetWithCollateral(
        address _swapperAddress,
        uint256 _collateralToSwap,
        uint256 _amountAssetOutMin,
        address[] calldata _path
    ) external nonReentrant isSolvent(msg.sender) returns (uint256 _amountAssetOut) {
        // Accrue interest if necessary
        _addInterest();

        // Update exchange rate and check if borrow is allowed, revert if not
        (bool _isBorrowAllowed, , ) = _updateExchangeRate();
        if (!_isBorrowAllowed) revert ExceedsMaxOracleDeviation();

        IERC20 _assetContract = assetContract;
        IERC20 _collateralContract = collateralContract;

        if (!swappers[_swapperAddress]) {
            revert BadSwapper();
        }
        if (_path[0] != address(_collateralContract)) {
            revert InvalidPath(address(_collateralContract), _path[0]);
        }
        if (_path[_path.length - 1] != address(_assetContract)) {
            revert InvalidPath(address(_assetContract), _path[_path.length - 1]);
        }

        // Effects: bookkeeping & write to state
        // Debit users collateral balance in preparation for swap, setting _recipient to address(this) means no transfer occurs
        _removeCollateral(_collateralToSwap, address(this), msg.sender);

        // Interactions
        _collateralContract.approve(_swapperAddress, _collateralToSwap);

        // Even though swappers are trusted, we verify the balance before and after swap
        uint256 _initialAssetBalance = _assetContract.balanceOf(address(this));
        ISwapper(_swapperAddress).swapExactTokensForTokens(
            _collateralToSwap,
            _amountAssetOutMin,
            _path,
            address(this),
            block.timestamp
        );
        uint256 _finalAssetBalance = _assetContract.balanceOf(address(this));

        // Note: VIOLATES CHECKS-EFFECTS-INTERACTION pattern, make sure function is NONREENTRANT
        // Effects: bookkeeping
        _amountAssetOut = _finalAssetBalance - _initialAssetBalance;
        if (_amountAssetOut < _amountAssetOutMin) {
            revert SlippageTooHigh(_amountAssetOutMin, _amountAssetOut);
        }

        VaultAccount memory _totalBorrow = totalBorrow;
        uint256 _sharesToRepay = _totalBorrow.toShares(_amountAssetOut, false);

        // Effects: write to state
        // Note: setting _payer to address(this) means no actual transfer will occur.  Contract already has funds
        _repayAsset(_totalBorrow, _amountAssetOut.toUint128(), _sharesToRepay.toUint128(), address(this), msg.sender);

        emit RepayAssetWithCollateral(msg.sender, _swapperAddress, _collateralToSwap, _amountAssetOut, _sharesToRepay);
    }
}
