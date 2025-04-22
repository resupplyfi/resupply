// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title ResupplyPairCore
 * @notice Based on code from Drake Evans and Frax Finance's lending pair core contract (https://github.com/FraxFinance/fraxlend), adapted for Resupply Finance
 */

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { ResupplyPairConstants } from "./ResupplyPairConstants.sol";
import { VaultAccount, VaultAccountingLibrary } from "../../libraries/VaultAccount.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IOracle } from "../../interfaces/IOracle.sol";
import { IRateCalculator } from "../../interfaces/IRateCalculator.sol";
import { ISwapper } from "../../interfaces/ISwapper.sol";
import { IResupplyRegistry } from "../../interfaces/IResupplyRegistry.sol";
import { ILiquidationHandler } from "../../interfaces/ILiquidationHandler.sol";
import { RewardDistributorMultiEpoch } from "../RewardDistributorMultiEpoch.sol";
import { WriteOffToken } from "../WriteOffToken.sol";
import { IERC4626 } from "../../interfaces/IERC4626.sol";
import { CoreOwnable } from "../../dependencies/CoreOwnable.sol";
import { IMintable } from "../../interfaces/IMintable.sol";


abstract contract ResupplyPairCore is CoreOwnable, ResupplyPairConstants, RewardDistributorMultiEpoch {
    using VaultAccountingLibrary for VaultAccount;
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    //forked fraxlend at version 3,0,0
    function version() external pure returns (uint256 _major, uint256 _minor, uint256 _patch) {
        _major = 3;
        _minor = 0;
        _patch = 2;
    }

    // ============================================================================================
    // Settings set by constructor()
    // ============================================================================================

    // Asset and collateral contracts
    address public immutable registry;
    IERC20 internal immutable debtToken;
    IERC20 public immutable collateral;
    IERC20 public immutable underlying;

    // LTV Settings
    /// @notice The maximum LTV allowed for this pair
    /// @dev 1e5 precision
    uint256 public maxLTV;

    //max borrow
    uint256 public borrowLimit;

    //Fees
    /// @notice The liquidation fee, given as a % of repayment amount
    /// @dev 1e5 precision
    uint256 public mintFee;
    uint256 public liquidationFee;
    /// @dev 1e18 precision
    uint256 public protocolRedemptionFee;
    uint256 public minimumRedemption = 100 * PAIR_DECIMALS; //minimum amount of debt to redeem
    uint256 public minimumLeftoverDebt = 10000 * PAIR_DECIMALS; //minimum amount of assets left over via redemptions
    uint256 public minimumBorrowAmount = 1000 * PAIR_DECIMALS; //minimum amount of assets to borrow
    

    // Interest Rate Calculator Contract
    IRateCalculator public rateCalculator; // For complex rate calculations

    // Swapper
    mapping(address => bool) public swappers; // approved swapper addresses

    // Metadata
    string public name;
    
    // ============================================================================================
    // Storage
    // ============================================================================================

    /// @notice Stores information about the current interest rate
    CurrentRateInfo public currentRateInfo;

    struct CurrentRateInfo {
        uint64 lastTimestamp;
        uint64 ratePerSec;
        uint128 lastShares;
    }

    /// @notice Stores information about the current exchange rate. Collateral:Asset ratio
    /// @dev Struct packed to save SLOADs. Amount of Collateral Token to buy 1e18 Asset Token
    ExchangeRateInfo public exchangeRateInfo;

    struct ExchangeRateInfo {
        address oracle;
        uint96 lastTimestamp;
        uint256 exchangeRate;
    }

    // Contract Level Accounting
    VaultAccount public totalBorrow; // amount = total borrow amount with interest accrued, shares = total shares outstanding
    uint256 public claimableFees; //amount of interest gained that is claimable as fees
    uint256 public claimableOtherFees; //amount of redemption/mint fees claimable by protocol
    WriteOffToken immutable public redemptionWriteOff; //token to keep track of redemption write offs

    // User Level Accounting
    /// @notice Stores the balance of collateral for each user
    mapping(address => uint256) internal _userCollateralBalance; // amount of collateral each user is backed
    /// @notice Stores the balance of borrow shares for each user
    mapping(address => uint256) internal _userBorrowShares; // represents the shares held by individuals

    

    // ============================================================================================
    // Constructor
    // ============================================================================================

    /// @notice The ```constructor``` function is called on deployment
    /// @param _core Core contract address
    /// @param _configData abi.encode(address _collateral, address _oracle, address _rateCalculator, uint256 _maxLTV, uint256 _borrowLimit, uint256 _liquidationFee, uint256 _mintFee, uint256 _protocolRedemptionFee)
    /// @param _immutables abi.encode(address _registry)
    /// @param _customConfigData abi.encode(address _name, address _govToken, address _underlyingStaking, uint256 _stakingId)
    constructor(
        address _core,
        bytes memory _configData,
        bytes memory _immutables,
        bytes memory _customConfigData
    ) CoreOwnable(_core){
        (address _registry) = abi.decode(
            _immutables,
            (address)
        );
        registry = _registry;
        debtToken = IERC20(IResupplyRegistry(registry).token());
        {
            (
                address _collateral,
                address _oracle,
                address _rateCalculator,
                uint256 _maxLTV,
                uint256 _initialBorrowLimit,
                uint256 _liquidationFee,
                uint256 _mintFee,
                uint256 _protocolRedemptionFee
            ) = abi.decode(
                    _configData,
                    (address, address, address, uint256, uint256, uint256, uint256, uint256)
                );

            // Pair Settings
            collateral = IERC20(_collateral);
            if(IERC20Metadata(_collateral).decimals() != 18){
                revert InvalidParameter();
            }
            underlying = IERC20(IERC4626(_collateral).asset());
            if(IERC20Metadata(address(underlying)).decimals() != 18){
                revert InvalidParameter();
            }
            // approve so this contract can deposit
            underlying.forceApprove(_collateral, type(uint256).max);
            currentRateInfo.lastShares = uint128(IERC4626(_collateral).convertToShares(PAIR_DECIMALS));
            exchangeRateInfo.oracle = _oracle;
            rateCalculator = IRateCalculator(_rateCalculator);
            borrowLimit = _initialBorrowLimit;

            //Liquidation Fee Settings
            liquidationFee = _liquidationFee;
            mintFee = _mintFee;
            protocolRedemptionFee = _protocolRedemptionFee;

            // set maxLTV
            maxLTV = _maxLTV;
        }

        //starting reward types
        redemptionWriteOff = new WriteOffToken(address(this));
        _insertRewardToken(address(redemptionWriteOff));//add redemption token as a reward
        //set the redemption token as non claimable via getReward
        rewards[0].is_non_claimable = true;

        {
            (string memory _name,,,) = abi.decode(
                _customConfigData,
                (string, address, address, uint256)
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
    // Helpers
    // ============================================================================================


    //get total collateral, either parked here or staked 
    function totalCollateral() public view virtual returns(uint256 _totalCollateralBalance);

    function userBorrowShares(address _account) public view returns(uint256 borrowShares){
        borrowShares = _userBorrowShares[_account];

        uint256 globalEpoch = currentRewardEpoch;
        uint256 userEpoch = userRewardEpoch[_account];

        if(userEpoch < globalEpoch){
            //need to calculate shares while keeping this as a view function
            for(;;){
                //reduce shares by refactoring amount
                borrowShares /= SHARE_REFACTOR_PRECISION;
                unchecked {
                    userEpoch += 1;
                }
                if(userEpoch == globalEpoch){
                    break;
                }
            }
        }
    }

    //get _userCollateralBalance minus redemption tokens
    function userCollateralBalance(address _account) public nonReentrant returns(uint256 _collateralAmount){
        _syncUserRedemptions(_account);

        _collateralAmount = _userCollateralBalance[_account];

        //since there are some very small dust during distribution there could be a few wei
        //in user collateral that is over total collateral. clamp to total
        uint256 total = totalCollateral();
        _collateralAmount = _collateralAmount > total ? total : _collateralAmount;
    }

    /// @notice The ```totalDebtAvailable``` function returns the total balance of debt tokens in the contract
    /// @return The balance of debt tokens held by contract
    function totalDebtAvailable() external view returns (uint256) {
        (,,, VaultAccount memory _totalBorrow) = previewAddInterest();
        
        return _totalDebtAvailable(_totalBorrow);
    }

    /// @notice The ```_totalDebtAvailable``` function returns the total amount of debt that can be issued on this pair
    /// @param _totalBorrow Total borrowed amount, inclusive of interest
    /// @return The amount of debt that can be issued
    function _totalDebtAvailable(VaultAccount memory _totalBorrow) internal view returns (uint256) {
        uint256 _borrowLimit = borrowLimit;
        uint256 borrowable = _borrowLimit > _totalBorrow.amount ? _borrowLimit - _totalBorrow.amount : 0;

        return borrowable > type(uint128).max ? type(uint128).max : borrowable; 
    }

    function currentUtilization() external view returns (uint256) {
        uint256 _borrowLimit = borrowLimit;
        if(_borrowLimit == 0){
            return PAIR_DECIMALS;
        }
        (,,, VaultAccount memory _totalBorrow) = previewAddInterest();
        return _totalBorrow.amount * PAIR_DECIMALS / _borrowLimit;
    }

    /// @notice The ```_isSolvent``` function determines if a given borrower is solvent given an exchange rate
    /// @param _borrower The borrower address to check
    /// @param _exchangeRate The exchange rate, i.e. the amount of collateral to buy 1e18 asset
    /// @return Whether borrower is solvent
    function _isSolvent(address _borrower, uint256 _exchangeRate) internal view returns (bool) {
        uint256 _maxLTV = maxLTV;
        if (_maxLTV == 0) return true;
        //must look at borrow shares of current epoch so user helper function
        //user borrow shares should be synced before _isSolvent is called
        uint256 _borrowerAmount = totalBorrow.toAmount(_userBorrowShares[_borrower], true);
        if (_borrowerAmount == 0) return true;
        
        //anything that calls _isSolvent will call _syncUserRedemptions beforehand
        uint256 _collateralAmount = _userCollateralBalance[_borrower];
        if (_collateralAmount == 0) return false;

        uint256 _ltv = ((_borrowerAmount * _exchangeRate * LTV_PRECISION) / EXCHANGE_PRECISION) / _collateralAmount;
        return _ltv <= _maxLTV;
    }

    function _isSolventSync(address _borrower, uint256 _exchangeRate) internal returns (bool){
         //checkpoint rewards and sync _userCollateralBalance
        _syncUserRedemptions(_borrower);
        return _isSolvent(_borrower, _exchangeRate);
    }

    // ============================================================================================
    // Modifiers
    // ============================================================================================

    /// @notice Checks for solvency AFTER executing contract code
    /// @param _borrower The borrower whose solvency we will check
    modifier isSolvent(address _borrower) {
        //checkpoint rewards and sync _userCollateralBalance before doing other actions
        _syncUserRedemptions(_borrower);
        _;
        ExchangeRateInfo memory _exchangeRateInfo = exchangeRateInfo;

        if (!_isSolvent(_borrower, _exchangeRateInfo.exchangeRate)) {
            revert Insolvent(
                totalBorrow.toAmount(_userBorrowShares[_borrower], true),
                _userCollateralBalance[_borrower], //_issolvent sync'd so take base _userCollateral
                _exchangeRateInfo.exchangeRate
            );
        }
    }

    // ============================================================================================
    // Reward Implementation
    // ============================================================================================

    function _isRewardManager() internal view override returns(bool){
        return msg.sender == address(core) || msg.sender == IResupplyRegistry(registry).rewardHandler();
    }

    function _fetchIncentives() internal override{
        IResupplyRegistry(registry).claimRewards(address(this));
    }

    function _totalRewardShares() internal view override returns(uint256){
        return totalBorrow.shares;
    }

    function _userRewardShares(address _account) internal view override returns(uint256){
        return _userBorrowShares[_account];
    }

    function _increaseUserRewardEpoch(address _account, uint256 _currentUserEpoch) internal override{
        //convert shares to next epoch shares
        //share refactoring will never be 0
        _userBorrowShares[_account] = _userBorrowShares[_account] / SHARE_REFACTOR_PRECISION;
        //update user reward epoch
        userRewardEpoch[_account] = _currentUserEpoch + 1;
    }

    function earned(address _account) public override returns(EarnedData[] memory claimable){
        EarnedData[] memory earneddata = super.earned(_account);
        uint256 rewardCount = earneddata.length - 1;
        claimable = new EarnedData[](rewardCount);

        //remove index 0 as we dont need to report the write off tokens
        for (uint256 i = 1; i <= rewardCount; ) {
            claimable[i-1].amount = earneddata[i].amount;
            claimable[i-1].token = earneddata[i].token;
            unchecked{ i += 1; }
        }
    }

    function _checkAddToken(address _address) internal view virtual override returns(bool){
        if(_address == address(collateral)) return false;
        if(_address == address(debtToken)) return false;
        return true;
    }

    // ============================================================================================
    // Underlying Staking
    // ============================================================================================

    function _stakeUnderlying(uint256 _amount) internal virtual;

    function _unstakeUnderlying(uint256 _amount) internal virtual;

    // ============================================================================================
    // Functions: Interest Accumulation and Adjustment
    // ============================================================================================

    /// @notice The ```AddInterest``` event is emitted when interest is accrued by borrowers
    /// @param interestEarned The total interest accrued by all borrowers
    /// @param rate The interest rate used to calculate accrued interest
    event AddInterest(uint256 interestEarned, uint256 rate);

    /// @notice The ```UpdateRate``` event is emitted when the interest rate is updated
    /// @param oldRatePerSec The old interest rate (per second)
    /// @param oldShares previous used shares
    /// @param newRatePerSec The new interest rate (per second)
    /// @param newShares new shares
    event UpdateRate(
        uint256 oldRatePerSec,
        uint128 oldShares,
        uint256 newRatePerSec,
        uint128 newShares
    );

    /// @notice The ```addInterest``` function is a public implementation of _addInterest and allows 3rd parties to trigger interest accrual
    /// @param _returnAccounting Whether to return additional accounting data
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
            _newCurrentRateInfo.lastShares = _results.newShares;

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
        uint128 newShares;
        uint256 interestEarned;
        VaultAccount totalBorrow;
    }

    /// @notice The ```_calculateInterest``` function calculates the interest to be accrued and the new interest rate info
    /// @param _currentRateInfo The current rate info
    /// @return _results The results of the interest calculation
    function _calculateInterest(
        CurrentRateInfo memory _currentRateInfo
    ) internal view returns (InterestCalculationResults memory _results) {
        // Short circuit if interest already calculated this block
        if (_currentRateInfo.lastTimestamp < block.timestamp) {
            // Indicate that interest is updated and calculated
            _results.isInterestUpdated = true;

            // Write return values and use these to save gas
            _results.totalBorrow = totalBorrow;

            // Time elapsed since last interest update
            uint256 _deltaTime = block.timestamp - _currentRateInfo.lastTimestamp;

            // Request new interest rate and full utilization rate from the rate calculator
            (_results.newRate, _results.newShares) = IRateCalculator(rateCalculator).getNewRate(
                address(collateral),
                _deltaTime,
                _currentRateInfo.lastShares
            );

            // Calculate interest accrued
            _results.interestEarned = (_deltaTime * _results.totalBorrow.amount * _results.newRate) / RATE_PRECISION;

            // Accrue interest (if any) and fees if no overflow
            if (
                _results.interestEarned > 0 &&
                _results.interestEarned + _results.totalBorrow.amount <= type(uint128).max
            ) {
                // Increment totalBorrow by interestEarned
                _results.totalBorrow.amount += uint128(_results.interestEarned);
            }else{
                //reset interest earned
                _results.interestEarned = 0;
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
                _currentRateInfo.lastShares,
                _results.newRate,
                _results.newShares
            );
            emit AddInterest(_interestEarned, _results.newRate);

            // overwrite original values
            _currentRateInfo.ratePerSec = _results.newRate;
            _currentRateInfo.lastShares = _results.newShares;
            _currentRateInfo.lastTimestamp = uint64(block.timestamp);

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
    /// @param exchangeRate The exchange rate
    event UpdateExchangeRate(uint256 exchangeRate);

    /// @notice The ```updateExchangeRate``` function is the external implementation of _updateExchangeRate.
    /// @dev This function is invoked at most once per block as these queries can be expensive
    /// @return _exchangeRate The exchange rate
    function updateExchangeRate()
        external
        nonReentrant
        returns (uint256 _exchangeRate)
    {
        return _updateExchangeRate();
    }

    /// @notice The ```_updateExchangeRate``` function retrieves the latest exchange rate. i.e how much collateral to buy 1e18 asset.
    /// @dev This function is invoked at most once per block as these queries can be expensive
    /// @return _exchangeRate The exchange rate
    function _updateExchangeRate()
        internal
        returns (uint256 _exchangeRate)
    {
        // Pull from storage to save gas and set default return values
        ExchangeRateInfo memory _exchangeRateInfo = exchangeRateInfo;

        // Get the latest exchange rate from the oracle
        //convert price of collateral as debt is priced in terms of collateral amount (inverse)
        _exchangeRate = 1e36 / IOracle(_exchangeRateInfo.oracle).getPrices(address(collateral));
        
        //skip storage writes if value doesnt change
        if (_exchangeRate != _exchangeRateInfo.exchangeRate) {

            // Effects: Bookkeeping and write to storage
            _exchangeRateInfo.lastTimestamp = uint96(block.timestamp);
            _exchangeRateInfo.exchangeRate = _exchangeRate;
            exchangeRateInfo = _exchangeRateInfo;
            emit UpdateExchangeRate(_exchangeRate);
        }
    }

    // ============================================================================================
    // Functions: Lending
    // ============================================================================================

    // ONLY Protocol can lend

    // ============================================================================================
    // Functions: Borrowing
    // ============================================================================================

    //sync user collateral by removing account of userCollateralBalance based on
    //how many "claimable" redemption tokens are available to the user
    //should be called before anything with userCollateralBalance is used
    function _syncUserRedemptions(address _account) internal{
        //sync rewards first
        _checkpoint(_account);

        //get token count (divide by LTV_PRECISION as precision is padded)
        uint256 rTokens = claimable_reward[address(redemptionWriteOff)][_account] / LTV_PRECISION;
        //reset claimables
        claimable_reward[address(redemptionWriteOff)][_account] = 0;

        //remove from collateral balance the number of rtokens the user has
        uint256 currentUserBalance = _userCollateralBalance[_account];
        _userCollateralBalance[_account] = currentUserBalance >= rTokens ? currentUserBalance - rTokens : 0;
    }

    /// @notice The ```Borrow``` event is emitted when a borrower increases their position
    /// @param _borrower The borrower whose account was debited
    /// @param _receiver The address to which the Asset Tokens were transferred
    /// @param _borrowAmount The amount of Asset Tokens transferred
    /// @param _sharesAdded The number of Borrow Shares the borrower was debited
    /// @param _mintFees The amount of mint fees incurred
    event Borrow(
        address indexed _borrower,
        address indexed _receiver,
        uint256 _borrowAmount,
        uint256 _sharesAdded,
        uint256 _mintFees
    );

    /// @notice The ```_borrow``` function is the internal implementation for borrowing assets
    /// @param _borrowAmount The amount of the Asset Token to borrow
    /// @param _receiver The address to receive the Asset Tokens
    /// @return _sharesAdded The amount of borrow shares the msg.sender will be debited
    function _borrow(uint128 _borrowAmount, address _receiver) internal returns (uint256 _sharesAdded) {
        // Get borrow accounting from storage to save gas
        VaultAccount memory _totalBorrow = totalBorrow;

        if(_borrowAmount < minimumBorrowAmount){
            revert InsufficientBorrowAmount();
        }

        //mint fees
        uint256 debtForMint = (_borrowAmount * (LIQ_PRECISION + mintFee) / LIQ_PRECISION);

        // Check available capital
        uint256 _assetsAvailable = _totalDebtAvailable(_totalBorrow);
        if (_assetsAvailable < debtForMint) {
            revert InsufficientDebtAvailable(_assetsAvailable, debtForMint);
        }
        
        // Calculate the number of shares to add based on the amount to borrow
        _sharesAdded = _totalBorrow.toShares(debtForMint, true);

        //combine current shares and new shares
        uint256 newTotalShares = _totalBorrow.shares + _sharesAdded;

        // Effects: Bookkeeping to add shares & amounts to total Borrow accounting
        _totalBorrow.amount += debtForMint.toUint128();
        _totalBorrow.shares = newTotalShares.toUint128();

        // Effects: write back to storage
        totalBorrow = _totalBorrow;
        _userBorrowShares[msg.sender] += _sharesAdded;

        uint256 otherFees = debtForMint > _borrowAmount ? debtForMint - _borrowAmount : 0;
        if (otherFees > 0) claimableOtherFees += otherFees;

        // Interactions
        IResupplyRegistry(registry).mint(_receiver, _borrowAmount);
        
        emit Borrow(msg.sender, _receiver, _borrowAmount, _sharesAdded, otherFees);
    }

    /// @notice The ```borrow``` function allows a user to open/increase a borrow position
    /// @dev Borrower must call ```ERC20.approve``` on the Collateral Token contract if applicable
    /// @param _borrowAmount The amount to borrow
    /// @param _underlyingAmount The amount of underlying tokens to transfer to Pair
    /// @param _receiver The address which will receive the Asset Tokens
    /// @return _shares The number of borrow Shares the msg.sender will be debited
    function borrow(
        uint256 _borrowAmount,
        uint256 _underlyingAmount,
        address _receiver
    ) external nonReentrant isSolvent(msg.sender) returns (uint256 _shares) {
        if (_receiver == address(0)) revert InvalidReceiver();

        // Accrue interest if necessary
        _addInterest();

        // Update _exchangeRate
        _updateExchangeRate();

        // Only add collateral if necessary
        if (_underlyingAmount > 0) {
            //pull underlying and deposit in vault
            underlying.safeTransferFrom(msg.sender, address(this), _underlyingAmount);
            uint256 collateralShares = IERC4626(address(collateral)).deposit(_underlyingAmount, address(this));
            //add collateral to msg.sender
            _addCollateral(address(this), collateralShares, msg.sender);
        }

        // Effects: Call internal borrow function
        _shares = _borrow(_borrowAmount.toUint128(), _receiver);
    }

    /// @notice The ```AddCollateral``` event is emitted when a borrower adds collateral to their position
    /// @param borrower The borrower account for which the collateral should be credited
    /// @param collateralAmount The amount of Collateral Token to be transferred
    event AddCollateral(address indexed borrower, uint256 collateralAmount);

    /// @notice The ```_addCollateral``` function is an internal implementation for adding collateral to a borrowers position
    /// @param _sender The source of funds for the new collateral
    /// @param _collateralAmount The amount of Collateral Token to be transferred
    /// @param _borrower The borrower account for which the collateral should be credited
    function _addCollateral(address _sender, uint256 _collateralAmount, address _borrower) internal {
        _userCollateralBalance[_borrower] += _collateralAmount;
        if (_sender != address(this)) {
            collateral.safeTransferFrom(_sender, address(this), _collateralAmount);
        }
        //stake underlying
        _stakeUnderlying(_collateralAmount);

        emit AddCollateral(_borrower, _collateralAmount);
    }

    /// @notice The ```addCollateral``` function allows the caller to add Collateral Token to a borrowers position
    /// @dev msg.sender must call ERC20.approve() on the Collateral Token contract prior to invocation
    /// @param _collateralAmount The amount of Collateral Token to be added to borrower's position
    /// @param _borrower The account to be credited
    function addCollateralVault(uint256 _collateralAmount, address _borrower) external nonReentrant {
        if (_borrower == address(0)) revert InvalidReceiver();

        _addInterest();
        _addCollateral(msg.sender, _collateralAmount, _borrower);
    }

    /// @notice Allows depositing in terms of underlying asset, and have it converted to collateral shares to the borrower's position.
    /// @param _amount The amount of the underlying asset to deposit.
    /// @param _borrower The address of the borrower whose collateral balance will be credited.
    function addCollateral(uint256 _amount, address _borrower) external nonReentrant {
        if (_borrower == address(0)) revert InvalidReceiver();

        _addInterest();

        underlying.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 collateralShares = IERC4626(address(collateral)).deposit(_amount, address(this));
        _addCollateral(address(this), collateralShares, _borrower);
    }

    /// @notice The ```RemoveCollateral``` event is emitted when collateral is removed from a borrower's position
    /// @param _collateralAmount The amount of Collateral Token to be transferred
    /// @param _receiver The address to which Collateral Tokens will be transferred
    /// @param _borrower The address of the account in which collateral is being removed
    event RemoveCollateral(
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
        _userCollateralBalance[_borrower] -= _collateralAmount;

        //unstake underlying
        //NOTE: following will revert on underflow if total collateral < _collateralAmount
        _unstakeUnderlying(_collateralAmount);

        // Interactions
        if (_receiver != address(this)) {
            collateral.safeTransfer(_receiver, _collateralAmount);
        }
        emit RemoveCollateral(_collateralAmount, _receiver, _borrower);
    }

    /// @notice The ```removeCollateralVault``` function is used to remove collateral from msg.sender's borrow position
    /// @dev msg.sender must be solvent after invocation or transaction will revert
    /// @param _collateralAmount The amount of Collateral Token to transfer
    /// @param _receiver The address to receive the transferred funds
    function removeCollateralVault(
        uint256 _collateralAmount,
        address _receiver
    ) external nonReentrant isSolvent(msg.sender) {
        //note: isSolvent checkpoints msg.sender via _syncUserRedemptions

        if (_receiver == address(0)) revert InvalidReceiver();

        _addInterest();
        // Note: exchange rate is irrelevant when borrower has no debt shares
        if (_userBorrowShares[msg.sender] > 0) {
            _updateExchangeRate();
        }
        _removeCollateral(_collateralAmount, _receiver, msg.sender);
    }

    /// @notice The ```removeCollateral``` function is used to remove collateral from msg.sender's borrow position and redeem it for underlying tokens
    /// @dev msg.sender must be solvent after invocation or transaction will revert
    /// @param _collateralAmount The amount of Collateral Token to redeem
    /// @param _receiver The address to receive the redeemed underlying tokens
    function removeCollateral(
        uint256 _collateralAmount,
        address _receiver
    ) external nonReentrant isSolvent(msg.sender) {
        //note: isSolvent checkpoints msg.sender via _syncUserRedemptions

        if (_receiver == address(0)) revert InvalidReceiver();

        _addInterest();
        // Note: exchange rate is irrelevant when borrower has no debt shares
        if (_userBorrowShares[msg.sender] > 0) {
            _updateExchangeRate();
        }
        _removeCollateral(_collateralAmount, address(this), msg.sender);
        IERC4626(address(collateral)).redeem(_collateralAmount, _receiver, address(this));
    }

    /// @notice The ```Repay``` event is emitted whenever a debt position is repaid
    /// @param payer The address paying for the repayment
    /// @param borrower The borrower whose account will be credited
    /// @param amountToRepay The amount of Asset token to be transferred
    /// @param shares The amount of Borrow Shares which will be debited from the borrower after repayment
    event Repay(address indexed payer, address indexed borrower, uint256 amountToRepay, uint256 shares);

    /// @notice The ```_repay``` function is the internal implementation for repaying a borrow position
    /// @dev The payer must have called ERC20.approve() on the Asset Token contract prior to invocation
    /// @param _totalBorrow An in memory copy of the totalBorrow VaultAccount struct
    /// @param _amountToRepay The amount of Asset Token to transfer
    /// @param _shares The number of Borrow Shares the sender is repaying
    /// @param _payer The address from which funds will be transferred
    /// @param _borrower The borrower account which will be credited
    function _repay(
        VaultAccount memory _totalBorrow,
        uint128 _amountToRepay,
        uint128 _shares,
        address _payer,
        address _borrower
    ) internal {
        //checkpoint rewards for borrower before adjusting borrow shares
        _checkpoint(_borrower);

        // Effects: Bookkeeping
        _totalBorrow.amount -= _amountToRepay;
        _totalBorrow.shares -= _shares;

        // Effects: write user state
        uint256 usershares = _userBorrowShares[_borrower] - _shares;
        _userBorrowShares[_borrower] = usershares;
    
        //check that any remaining user amount is greater than minimumBorrowAmount
        if(usershares > 0 && _totalBorrow.toAmount(usershares, true) < minimumBorrowAmount){
            revert InsufficientBorrowAmount();
        }

        // Effects: write global state
        totalBorrow = _totalBorrow;

        // Interactions
        // burn from non-zero address.  zero address is only supplied during liquidations
        // for liqudations the handler will do the burning
        if (_payer != address(0)) {
            IMintable(address(debtToken)).burn(_payer, _amountToRepay);
        }
        emit Repay(_payer, _borrower, _amountToRepay, _shares);
    }

    /// @notice The ```repay``` function allows the caller to pay down the debt for a given borrower.
    /// @dev Caller must first invoke ```ERC20.approve()``` for the Asset Token contract
    /// @param _shares The number of Borrow Shares which will be repaid by the call
    /// @param _borrower The account for which the debt will be reduced
    /// @return _amountToRepay The amount of Asset Tokens which were burned to repay the Borrow Shares
    function repay(uint256 _shares, address _borrower) external nonReentrant returns (uint256 _amountToRepay) {
        if (_borrower == address(0)) revert InvalidReceiver();

        // Accrue interest if necessary
        _addInterest();

        // Calculate amount to repay based on shares
        VaultAccount memory _totalBorrow = totalBorrow;
        _amountToRepay = _totalBorrow.toAmount(_shares, true);

        // Execute repayment effects
        _repay(_totalBorrow, _amountToRepay.toUint128(), _shares.toUint128(), msg.sender, _borrower);
    }

    // ============================================================================================
    // Functions: Redemptions
    // ============================================================================================
    event Redeemed(
        address indexed _caller,
        uint256 _amount,
        uint256 _collateralFreed,
        uint256 _protocolFee,
        uint256 _debtReduction
    );

    /// @notice Allows redemption of the debt tokens for collateral
    /// @dev Only callable by the registry's redeemer contract
    /// @param _caller The address of the caller
    /// @param _amount The amount of debt tokens to redeem
    /// @param _totalFeePct Total fee to charge, expressed as a percentage of the stablecoin input; to be subdivided between protocol and borrowers.
    /// @param _receiver The address to receive the collateral tokens
    /// @return _collateralToken The address of the collateral token
    /// @return _collateralFreed The amount of collateral tokens returned to receiver
    function redeemCollateral(
        address _caller,
        uint256 _amount,
        uint256 _totalFeePct,
        address _receiver
    ) external nonReentrant returns(address _collateralToken, uint256 _collateralFreed){
        //check sender. must go through the registry's redemptionHandler
        if(msg.sender != IResupplyRegistry(registry).redemptionHandler()) revert InvalidRedemptionHandler();

        if (_receiver == address(0) || _receiver == address(this)) revert InvalidReceiver();

        if(_amount < minimumRedemption){
          revert MinimumRedemption();
        }

        // accrue interest if necessary
        _addInterest();

        //redemption fees
        //assuming 1% redemption fee(0.5% to protocol, 0.5% to borrowers) and a redemption of $100
        // reduce totalBorrow.amount by 99.5$
        // add 0.5$ to protocol earned fees
        // return 99$ of collateral
        // burn $100 of stables
        uint256 valueToRedeem = _amount * (EXCHANGE_PRECISION - _totalFeePct) / EXCHANGE_PRECISION;
        uint256 protocolFee = (_amount - valueToRedeem) * protocolRedemptionFee / EXCHANGE_PRECISION;
        uint256 debtReduction = _amount - protocolFee; // protocol fee portion is not burned

        //check if theres enough debt to write off
        VaultAccount memory _totalBorrow = totalBorrow;
        if(debtReduction > _totalBorrow.amount || _totalBorrow.amount - debtReduction < minimumLeftoverDebt ){
            revert InsufficientDebtToRedeem(); // size of request exceeeds total pair debt
        }

        _totalBorrow.amount -= uint128(debtReduction);

        //if after many redemptions the amount to shares ratio has deteriorated too far, then refactor
        //cast to uint256 to reduce chance of overflow
        if(uint256(_totalBorrow.amount) * SHARE_REFACTOR_PRECISION < _totalBorrow.shares){
            _increaseRewardEpoch(); //will do final checkpoint on previous total supply
            _totalBorrow.shares /= uint128(SHARE_REFACTOR_PRECISION);
        }

        // Effects: write to state
        totalBorrow = _totalBorrow;

        claimableOtherFees += protocolFee; //increase claimable fees

        // Update exchange rate
        uint256 _exchangeRate = _updateExchangeRate();
        //calc collateral units
        _collateralFreed = ((valueToRedeem * _exchangeRate) / EXCHANGE_PRECISION);
        
        _unstakeUnderlying(_collateralFreed);
        _collateralToken = address(collateral);
        IERC20(_collateralToken).safeTransfer(_receiver, _collateralFreed);

        //distribute write off tokens to adjust userCollateralbalances
        //padded with LTV_PRECISION for extra precision
        redemptionWriteOff.mint(_collateralFreed * LTV_PRECISION);

        emit Redeemed(_caller, _amount, _collateralFreed, protocolFee, debtReduction);
    }

    // ============================================================================================
    // Functions: Liquidations
    // ============================================================================================
    /// @notice The ```Liquidate``` event is emitted when a liquidation occurs
    /// @param _borrower The borrower account for which the liquidation occurred
    /// @param _collateralForLiquidator The amount of collateral token transferred to the liquidator
    /// @param _sharesLiquidated The number of borrow shares liquidated
    /// @param _amountLiquidatorToRepay The amount of asset tokens to be repaid by the liquidator
    event Liquidate(
        address indexed _borrower,
        uint256 _collateralForLiquidator,
        uint256 _sharesLiquidated,
        uint256 _amountLiquidatorToRepay
    );

    /// @notice The ```liquidate``` function allows a third party to repay a borrower's debt if they have become insolvent
    /// @dev Caller must invoke ```ERC20.approve``` on the Asset Token contract prior to calling ```Liquidate()```
    /// @param _borrower The account for which the repayment is credited and from whom collateral will be taken
    /// @return _collateralForLiquidator The amount of Collateral Token transferred to the liquidator
    function liquidate(
        address _borrower
    ) external nonReentrant returns (uint256 _collateralForLiquidator) {
        address liquidationHandler = IResupplyRegistry(registry).liquidationHandler();
        if(msg.sender != liquidationHandler) revert InvalidLiquidator();

        if (_borrower == address(0)) revert InvalidReceiver();

        // accrue interest if necessary
        _addInterest();

        // Update exchange rate and use the lower rate for liquidations
        uint256 _exchangeRate = _updateExchangeRate();

        // Check if borrower is solvent, revert if they are
        //_isSolventSync calls _syncUserRedemptions which checkpoints rewards and userCollateral
        if (_isSolventSync(_borrower, _exchangeRate)) {
            revert BorrowerSolvent();
        }

        // Read from state
        VaultAccount memory _totalBorrow = totalBorrow;
        uint256 _collateralBalance = _userCollateralBalance[_borrower];
        uint128 _borrowerShares = _userBorrowShares[_borrower].toUint128();

        // Checks & Calculations
        // Determine the liquidation amount in collateral units (i.e. how much debt liquidator is going to repay)
        uint256 _liquidationAmountInCollateralUnits = ((_totalBorrow.toAmount(_borrowerShares, false) *
            _exchangeRate) / EXCHANGE_PRECISION);

        // add fee for liquidation
        _collateralForLiquidator = (_liquidationAmountInCollateralUnits *
            (LIQ_PRECISION + liquidationFee)) / LIQ_PRECISION;

        // clamp to user collateral balance as we cant take more than that
        _collateralForLiquidator = _collateralForLiquidator > _collateralBalance ? _collateralBalance : _collateralForLiquidator;

        // Calculated here for use during repayment, grouped with other calcs before effects start
        uint128 _amountLiquidatorToRepay = (_totalBorrow.toAmount(_borrowerShares, true)).toUint128();

        emit Liquidate(
                _borrower,
                _collateralForLiquidator,
                _borrowerShares,
                _amountLiquidatorToRepay
            );

        // Effects & Interactions
        // repay using address(0) to skip burning (liquidationHandler will burn from insurance pool)
        _repay(
            _totalBorrow,
            _amountLiquidatorToRepay,
            _borrowerShares,
            address(0),
            _borrower
        );

        // Collateral is removed on behalf of borrower and sent to liquidationHandler
        // NOTE: isSolvent above checkpoints user with _syncUserRedemptions before removing collateral
        _removeCollateral(_collateralForLiquidator, liquidationHandler, _borrower);

        //call liquidation handler to distribute and burn debt
        ILiquidationHandler(liquidationHandler).processLiquidationDebt(address(collateral), _collateralForLiquidator, _amountLiquidatorToRepay);
    }

    // ============================================================================================
    // Functions: Leverage
    // ============================================================================================

    /// @notice The ```LeveragedPosition``` event is emitted when a borrower takes out a new leveraged position
    /// @param _borrower The account for which the debt is debited
    /// @param _swapperAddress The address of the swapper which conforms the FraxSwap interface
    /// @param _borrowAmount The amount of Asset Token to be borrowed to be borrowed
    /// @param _borrowShares The number of Borrow Shares the borrower is credited
    /// @param _initialUnderlyingAmount The amount of initial underlying Tokens supplied by the borrower
    /// @param _amountCollateralOut The amount of Collateral Token which was received for the Asset Tokens
    event LeveragedPosition(
        address indexed _borrower,
        address _swapperAddress,
        uint256 _borrowAmount,
        uint256 _borrowShares,
        uint256 _initialUnderlyingAmount,
        uint256 _amountCollateralOut
    );

    /// @notice The ```leveragedPosition``` function allows a user to enter a leveraged borrow position with minimal upfront Underlying tokens
    /// @dev Caller must invoke ```ERC20.approve()``` on the Underlying Token contract prior to calling function
    /// @param _swapperAddress The address of the whitelisted swapper to use to swap borrowed Asset Tokens for Collateral Tokens
    /// @param _borrowAmount The amount of Asset Tokens borrowed
    /// @param _initialUnderlyingAmount The initial amount of underlying Tokens supplied by the borrower
    /// @param _amountCollateralOutMin The minimum amount of Collateral Tokens to be received in exchange for the borrowed Asset Tokens
    /// @param _path An array containing the addresses of ERC20 tokens to swap.  Adheres to UniV2 style path params.
    /// @return _totalCollateralBalance The total amount of Collateral Tokens added to a users account (initial + swap)
    function leveragedPosition(
        address _swapperAddress,
        uint256 _borrowAmount,
        uint256 _initialUnderlyingAmount,
        uint256 _amountCollateralOutMin,
        address[] memory _path
    ) external nonReentrant isSolvent(msg.sender) returns (uint256 _totalCollateralBalance) {
        // Accrue interest if necessary
        _addInterest();

        // Update exchange rate
        _updateExchangeRate();

        IERC20 _debtToken = debtToken;
        IERC20 _collateral = collateral;

        if (!swappers[_swapperAddress]) {
            revert BadSwapper();
        }
        if (_path[0] != address(_debtToken)) {
            revert InvalidPath(address(_debtToken), _path[0]);
        }
        if (_path[_path.length - 1] != address(_collateral)) {
            revert InvalidPath(address(_collateral), _path[_path.length - 1]);
        }

        // Add initial underlying
        if (_initialUnderlyingAmount > 0) {
            underlying.safeTransferFrom(msg.sender, address(this), _initialUnderlyingAmount);
            uint256 collateralShares = IERC4626(address(collateral)).deposit(_initialUnderlyingAmount, address(this));
            _addCollateral(address(this), collateralShares, msg.sender);
            _totalCollateralBalance = collateralShares;
        }

        // Debit borrowers account
        // setting recipient to _swapperAddress allows us to skip a transfer (debt still goes to msg.sender)
        uint256 _borrowShares = _borrow(_borrowAmount.toUint128(), _swapperAddress);

        // Even though swappers are trusted, we verify the balance before and after swap
        uint256 _initialCollateralBalance = _collateral.balanceOf(address(this));
        ISwapper(_swapperAddress).swap(
            msg.sender,
            _borrowAmount,
            _path,
            address(this)
        );
        uint256 _finalCollateralBalance = _collateral.balanceOf(address(this));

        // Note: VIOLATES CHECKS-EFFECTS-INTERACTION pattern, make sure function is NONREENTRANT
        // Effects: bookkeeping & write to state
        uint256 _amountCollateralOut = _finalCollateralBalance - _initialCollateralBalance;
        if (_amountCollateralOut < _amountCollateralOutMin) {
            revert SlippageTooHigh(_amountCollateralOutMin, _amountCollateralOut);
        }

        // address(this) as _sender means no transfer occurs as the pair has already received the collateral during swap
        _addCollateral(address(this), _amountCollateralOut, msg.sender);

        _totalCollateralBalance += _amountCollateralOut;
        emit LeveragedPosition(
            msg.sender,
            _swapperAddress,
            _borrowAmount,
            _borrowShares,
            _initialUnderlyingAmount,
            _amountCollateralOut
        );
    }

    /// @notice The ```RepayWithCollateral``` event is emitted whenever ```repayWithCollateral()``` is invoked
    /// @param _borrower The borrower account for which the repayment is taking place
    /// @param _swapperAddress The address of the whitelisted swapper to use for token swaps
    /// @param _collateralToSwap The amount of Collateral Token to swap and use for repayment
    /// @param _amountAssetOut The amount of Asset Token which was repaid
    /// @param _sharesRepaid The number of Borrow Shares which were repaid
    event RepayWithCollateral(
        address indexed _borrower,
        address _swapperAddress,
        uint256 _collateralToSwap,
        uint256 _amountAssetOut,
        uint256 _sharesRepaid
    );

    /// @notice The ```repayWithCollateral``` function allows a borrower to repay their debt using existing collateral in contract
    /// @param _swapperAddress The address of the whitelisted swapper to use for token swaps
    /// @param _collateralToSwap The amount of Collateral Tokens to swap for Asset Tokens
    /// @param _amountOutMin The minimum amount of Asset Tokens to receive during the swap
    /// @param _path An array containing the addresses of ERC20 tokens to swap.  Adheres to UniV2 style path params.
    /// @return _amountOut The amount of Asset Tokens received for the Collateral Tokens, the amount the borrowers account was credited
    function repayWithCollateral(
        address _swapperAddress,
        uint256 _collateralToSwap,
        uint256 _amountOutMin,
        address[] calldata _path
    ) external nonReentrant isSolvent(msg.sender) returns (uint256 _amountOut) {
        // Accrue interest if necessary
        _addInterest();

        // Update exchange rate
        _updateExchangeRate();

        IERC20 _debtToken = debtToken;
        IERC20 _collateral = collateral;
        VaultAccount memory _totalBorrow = totalBorrow;

        if (!swappers[_swapperAddress]) {
            revert BadSwapper();
        }
        if (_path[0] != address(_collateral)) {
            revert InvalidPath(address(_collateral), _path[0]);
        }
        if (_path[_path.length - 1] != address(_debtToken)) {
            revert InvalidPath(address(_debtToken), _path[_path.length - 1]);
        }
        //in case of a full redemption/shutdown via protocol,
        //all user debt should be 0 and thus swapping to repay is unnecessary.
        //toShares below will also return an incorrect value.
        //in case of a full redemption, users can use the normal repayAsset with 0 cost
        //or just withdraw collateral via removeCollateral
        if(_totalBorrow.amount == 0){
            revert InsufficientBorrowAmount();
        }

        // Effects: bookkeeping & write to state
        // Debit users collateral balance and sends directly to the swapper
        // NOTE: isSolvent checkpoints msg.sender with _syncUserRedemptions
        _removeCollateral(_collateralToSwap, _swapperAddress, msg.sender);

        // Even though swappers are trusted, we verify the balance before and after swap
        uint256 _initialBalance = _debtToken.balanceOf(address(this));
        ISwapper(_swapperAddress).swap(
            msg.sender,
            _collateralToSwap,
            _path,
            address(this)
        );

        // Note: VIOLATES CHECKS-EFFECTS-INTERACTION pattern, make sure function is NONREENTRANT
        // Effects: bookkeeping
        _amountOut = _debtToken.balanceOf(address(this)) - _initialBalance;
        if (_amountOut < _amountOutMin) {
            revert SlippageTooHigh(_amountOutMin, _amountOut);
        }

        
        uint256 _sharesToRepay = _totalBorrow.toShares(_amountOut, false);

        //check if over user borrow shares or will revert
        uint256 currentUserBorrowShares = _userBorrowShares[msg.sender];
        if(_sharesToRepay > currentUserBorrowShares){
            //clamp
            _sharesToRepay = currentUserBorrowShares;

            //readjust token amount since shares changed
            _amountOut = _totalBorrow.toAmount(_sharesToRepay, true);
        }
        

        // Effects: write to state
        _repay(_totalBorrow, _amountOut.toUint128(), _sharesToRepay.toUint128(), address(this), msg.sender);

        //check for leftover stables that didnt go toward repaying debt
        uint256 leftover = debtToken.balanceOf(address(this)) - _initialBalance;
        if(leftover > 0){
            //send change back to user
            debtToken.transfer(msg.sender, leftover);
        }

        emit RepayWithCollateral(msg.sender, _swapperAddress, _collateralToSwap, _amountOut, _sharesToRepay);
    }
}