// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { CoreOwnable } from '../dependencies/CoreOwnable.sol';
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "../libraries/SafeERC20.sol";
import { IResupplyPair } from "../interfaces/IResupplyPair.sol";
import { IResupplyRegistry } from "../interfaces/IResupplyRegistry.sol";
import { IERC4626 } from "../interfaces/IERC4626.sol";

//Contract that interacts with pairs to perform redemptions
//Can swap out this contract for another to change logic on how redemption fees are calculated.
//for example can give fee discounts based on certain conditions (like utilization) to
//incentivize redemptions across multiple pools etc
contract RedemptionHandler is CoreOwnable{
    using SafeERC20 for IERC20;

    address public immutable registry;
    address public immutable debtToken;

    uint256 public baseRedemptionFee = 1e16; //1%

    event SetBaseRedemptionFee(uint256 _fee);

    constructor(address _core, address _registry) CoreOwnable(_core){
        registry = _registry;
        debtToken = IResupplyRegistry(_registry).token();
    }

    /// @notice Sets the base redemption fee.
    /// @dev This fee is not the effective fee. The effective fee is calculated at time of redemption via ``getRedemptionFee``.
    /// @param _fee The new base redemption fee, must be <= 1e18 (100%)
    function setBaseRedemptionFee(uint256 _fee) external onlyOwner{
        require(_fee <= 1e18, "!fee");
        baseRedemptionFee = _fee;
        emit SetBaseRedemptionFee(_fee);
    }

    //get max redeemable
    //based on fee, true max redeemable will be slightly larger than this value
    //this is just a quick estimate
    function getMaxRedeemable(address _pair) external view returns(uint256){
        //get max redeemable of pair
        (, , , IResupplyPair.VaultAccount memory _totalBorrow) = IResupplyPair(_pair).previewAddInterest();
        uint256 redeemable = IResupplyPair(_pair).minimumLeftoverAssets();
        redeemable = _totalBorrow.amount - redeemable;

        //get collateral max withdraw
        address vault = IResupplyPair(_pair).collateral();
        uint256 maxwithdraw = IERC4626(vault).maxWithdraw(_pair);

        //take lower of redeemable and maxwithdraw
        return redeemable > maxwithdraw ? maxwithdraw : redeemable;
    }

    /// @notice Calculate the base fee for a redemption. Fee serves to discount the total redemption value.
    function getRedemptionFee(address _pair, uint256 _amount) public view returns(uint256){
        return baseRedemptionFee;
    }

    /// @notice Redeem stablecoins for collateral from a pair
    /// @param _pair The address of the pair to redeem from
    /// @param _amount The amount of stablecoins to redeem
    /// @param _maxFeePct The maximum fee pct (in 1e18) that the caller will accept
    /// @param _receiver The address that will receive the withdrawn collateral
    /// @return _ amount of vault shares redeemed and sent to receiver
    function redeemCollateral (
        address _pair,
        uint256 _amount,
        uint256 _maxFeePct,
        address _receiver
    ) external returns(uint256){
        //pull redeeming tokens
        IERC20(debtToken).safeTransferFrom(msg.sender, address(this), _amount);

        //get fee
        uint256 fee = getRedemptionFee(_pair, _amount);
        //check against maxfee to avoid frontrun
        require(fee <= _maxFeePct, "fee > maxFee");

        //redeem
        IResupplyPair(_pair).redeemCollateral(_amount, fee, address(this));

        //withdraw
        address vault = IResupplyPair(_pair).collateral();
        uint256 collateralBalance = IERC20(vault).balanceOf(address(this));
        IERC4626(vault).redeem(collateralBalance, _receiver, address(this));
        return collateralBalance;
    }

}