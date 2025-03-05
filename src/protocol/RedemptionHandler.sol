// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { CoreOwnable } from '../dependencies/CoreOwnable.sol';
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "../libraries/SafeERC20.sol";
import { IResupplyPair } from "../interfaces/IResupplyPair.sol";
import { IResupplyRegistry } from "../interfaces/IResupplyRegistry.sol";
import { IOracle } from "../interfaces/IOracle.sol";
import { IERC4626 } from "../interfaces/IERC4626.sol";
import { IMintable } from "../interfaces/IMintable.sol";

//Contract that interacts with pairs to perform redemptions
//Can swap out this contract for another to change logic on how redemption fees are calculated.
//for example can give fee discounts based on certain conditions (like utilization) to
//incentivize redemptions across multiple pools etc
contract RedemptionHandler is CoreOwnable{
    using SafeERC20 for IERC20;

    address public immutable registry;
    address public immutable debtToken;

    uint256 public baseRedemptionFee = 1e16; //1%
    uint256 public constant PRECISION = 1e18;

    struct RedeemptionRateInfo {
        uint64 timestamp;  //time since last update
        uint192 usage;  //usage weight, defined by % of pair redeemed. thus a pair redeemed for 2% three times will have a weight of 6
    }
    mapping(address => RedeemptionRateInfo) public ratingData;
    uint256 public usageDecayRate = 1e17 / uint256(7 days); //10% per week
    uint256 public maxUsage = 3e17; //max usage of 30%. any thing above 30% will be 0 discount.  linearly scale between 0 and maxusage
    uint256 public maxDiscount = 5e14; //up to 0.05% discount

    address public underlyingOracle;

    event SetBaseRedemptionFee(uint256 _fee);
    event SetDiscountInfo(uint256 _fee, uint256 _maxUsage, uint256 _maxDiscount);
    event SetUnderlyingOracle(address indexed _oracle);

    constructor(address _core, address _registry, address _underlyingOracle) CoreOwnable(_core){
        registry = _registry;
        debtToken = IResupplyRegistry(_registry).token();
        underlyingOracle = _underlyingOracle;
        emit SetUnderlyingOracle(_underlyingOracle);
    }

    /// @notice Sets the base redemption fee.
    /// @dev This fee is not the effective fee. The effective fee is calculated at time of redemption via ``getRedemptionFeePct``.
    /// @param _fee The new base redemption fee, must be <= 1e18 (100%)
    function setBaseRedemptionFee(uint256 _fee) external onlyOwner{
        require(_fee <= 1e18, "fee too high");
        require(_fee >= maxDiscount, "fee higher than max discount");
        baseRedemptionFee = _fee;
        emit SetBaseRedemptionFee(_fee);
    }

    function setDiscountInfo(uint256 _rate, uint256 _maxUsage, uint256 _maxDiscount) external onlyOwner{
        require(_maxDiscount <= baseRedemptionFee, "max discount exceeds base redemption fee");
        usageDecayRate = _rate;
        maxUsage = _maxUsage;
        maxDiscount = _maxDiscount;
        emit SetDiscountInfo(_rate, _maxUsage, _maxDiscount);
    }

    function setUnderlyingOracle(address _oracle) external onlyOwner{
        underlyingOracle = _oracle;
        emit SetUnderlyingOracle(_oracle);
    }

    /// @notice Estimates the maximum amount of debt that can be redeemed from a pair
    function getMaxRedeemableDebt(address _pair) external view returns(uint256){
        (,,,IResupplyPair.VaultAccount memory _totalBorrow) = IResupplyPair(_pair).previewAddInterest();
        
        uint256 minLeftoverDebt = IResupplyPair(_pair).minimumLeftoverDebt();
        if (_totalBorrow.amount < minLeftoverDebt) return 0;

        return _totalBorrow.amount - minLeftoverDebt;
    }

    /// @notice Calculates the total redemption fee as a percentage of the redemption amount.
    function getRedemptionFeePct(address _pair, uint256 _amount) public view returns(uint256){
        //get fee
        (uint256 feePct,) = _getRedemptionFee(_pair, _amount);
        return feePct;
    }

    function _getRedemptionFee(address _pair, uint256 _amount) internal view returns(uint256, RedeemptionRateInfo memory){
        (, , , IResupplyPair.VaultAccount memory _totalBorrow) = IResupplyPair(_pair).previewAddInterest();
        
        //determine the weight of this current redemption by dividing by pair's total borrow
        uint256 weightOfRedeem;
        if (_totalBorrow.amount != 0) weightOfRedeem = _amount * PRECISION / _totalBorrow.amount;

        //update current data with decay rate
        RedeemptionRateInfo memory rdata = ratingData[_pair];
        
        //only decay if this pair has been used before
        if(rdata.timestamp != 0){
            //reduce useage by time difference since last redemption
            uint192 decay = uint192((block.timestamp - rdata.timestamp) * usageDecayRate);
            //set the pair's usage or weight
            rdata.usage = rdata.usage < decay ? 0 : rdata.usage - decay;
        }
        //update timestamp
        rdata.timestamp = uint64(block.timestamp);
        
        //use halfway point as the current weight for fee calc
        //using pre weight would have high discount, using post weight would have low discount
        //just use the half way point by using current + half the newly added weight
        uint256 halfway = rdata.usage + (weightOfRedeem/2);
        
        uint256 _maxusage = maxUsage;

        //add new weight to the struct
        rdata.usage += uint192(weightOfRedeem);
        //clamp to max usage
        if(rdata.usage > uint192(_maxusage)){
            rdata.usage = uint192(_maxusage);
        }
    
        //calculate the discount and final fee (base fee minus discount)
        
        //first get how close we are to _maxusage by taking difference.
        //if halfway is >= to _maxusage then discount is 0.
        //if halfway is == to 0 then discount equals our max usage
        uint256 discount = _maxusage > halfway ? _maxusage - halfway : 0;
        
        //convert the above value to a percentage with precision 1e18
        //if halfway is 8 units of usage then discount is 2 (10-8)
        //thus below should convert to 20%  (2 is 20% of the max usage 10)
        discount = (discount * PRECISION / _maxusage); //discount is now a 1e18 precision % 
        
        //take above percentage of maxDiscount as our final discount
        //above example is 20% so a 0.2 max discount * 20% will be 0.04 discount (2e15 * 20% = 4e14)
        discount = (maxDiscount * discount / PRECISION);// get % of maxDiscount
        
        //remove from base fee the discount and return
        //above example will be 1.0 - 0.04 = 0.96% fee (1e16 - 4e14)
        uint256 redemptionfee = baseRedemptionFee - discount;

        //check if underlying being redeemed is overly priced
        if(underlyingOracle != address(0)){
            uint256 price = IOracle(underlyingOracle).getPrices(IResupplyPair(_pair).underlying());
            if(price > 1e18){
                //if overly priced then add on to fee
                redemptionfee += (price - 1e18);
            }
        }

        return (redemptionfee, rdata);
    }


    /// @notice Redeem stablecoins for collateral from a pair
    /// @param _pair The address of the pair to redeem from
    /// @param _amount The amount of stablecoins to redeem
    /// @param _maxFeePct The maximum fee pct (in 1e18) that the caller will accept
    /// @param _receiver The address that will receive the withdrawn collateral
    /// @param _redeemToUnderlying Whether to unwrap the collateral to the underlying asset
    /// @return _ amount received of either collateral shares or underlying, depending on `_redeemToUnderlying`
    function redeemFromPair (
        address _pair,
        uint256 _amount,
        uint256 _maxFeePct,
        address _receiver,
        bool _redeemToUnderlying
    ) external returns(uint256){
        //get fee
        (uint256 feePct, RedeemptionRateInfo memory rdata) = _getRedemptionFee(_pair, _amount);
        
        //check against maxfee to avoid frontrun
        require(feePct <= _maxFeePct, "fee > maxFee");

        //write new rating data to state
        ratingData[_pair] = rdata;

        address returnToAddress = address(this);
        if(!_redeemToUnderlying){
            //if directly redeeming lending collateral, send directly to receiver
            returnToAddress = _receiver;
        }
        (address _collateral, uint256 _returnedCollateral) = IResupplyPair(_pair).redeemCollateral(
            msg.sender,
            _amount,
            feePct,
            returnToAddress
        );

        IMintable(debtToken).burn(msg.sender, _amount);

        //withdraw to underlying
        //if false receiver will have already received during redeemCollateral()
        //unwrap only if true
        if(_redeemToUnderlying){
            return IERC4626(_collateral).redeem(_returnedCollateral, _receiver, address(this));
        }
        
        return _returnedCollateral;
    }

    function previewRedeem(address _pair, uint256 _amount) external view returns(uint256 _returnedUnderlying, uint256 _returnedCollateral, uint256 _fee){
        //get fee
        (_fee, ) = _getRedemptionFee(_pair, _amount);

        //value to redeem
        uint256 valueToRedeem = _amount * (1e18 - _fee) / 1e18;

        //add interest and check amount bounds
        (,,, IResupplyPair.VaultAccount memory _totalBorrow) = IResupplyPair(_pair).previewAddInterest();
        uint256 minLeftoverDebt = IResupplyPair(_pair).minimumLeftoverDebt();
        uint256 protocolFee = (_amount - valueToRedeem) * IResupplyPair(_pair).protocolRedemptionFee() / 1e18;
        uint256 debtReduction = _amount - protocolFee;

        //return 0 if given amount is out of bounds
        if(debtReduction > _totalBorrow.amount || _totalBorrow.amount - debtReduction < minLeftoverDebt ){
            return (0,0, _fee);
        }

        //get exchange
        (address oracle, , ) = IResupplyPair(_pair).exchangeRateInfo();
        address collateralVault = IResupplyPair(_pair).collateral();

        uint256 exchangeRate = IOracle(oracle).getPrices(collateralVault);
        //convert price of collateral as debt is priced in terms of collateral amount (inverse)
        exchangeRate = 1e36 / exchangeRate;

        //calc collateral units
        _returnedCollateral = ((valueToRedeem * exchangeRate) / 1e18);

        //preview redeem of underlying
        _returnedUnderlying = IERC4626(collateralVault).previewRedeem(_returnedCollateral);
    }

}