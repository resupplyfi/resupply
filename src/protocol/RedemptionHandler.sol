// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { CoreOwnable } from '../dependencies/CoreOwnable.sol';
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "../libraries/SafeERC20.sol";
import { IResupplyPair } from "../interfaces/IResupplyPair.sol";
import { IResupplyRegistry } from "../interfaces/IResupplyRegistry.sol";

//Contract that interacts with pairs to perform redemptions
//Can swap out this contract for another to change logic on how redemption fees are calculated.
//for example can give fee discounts based on certain conditions (like utilization) to
//incentivize redemptions across multiple pools etc
contract RedemptionHandler is CoreOwnable{
    using SafeERC20 for IERC20;

    address public immutable registry;
    address public immutable redemptionToken;

    uint256 public baseRedemptionFee = 1e16; //1%

    event SetBaseRedemptionFee(uint256 _fee);

    constructor(address _core, address _registry, address _redemptionToken) CoreOwnable(_core){
        registry = _registry;
        redemptionToken = _redemptionToken;
    }

    function setBaseRedemptionFee(uint256 _fee) external onlyOwner{
        require(_fee <= 1e18, "!fee");
        baseRedemptionFee = _fee;
        emit SetBaseRedemptionFee(_fee);
    }

    //get max redeemable
    //based on fee, true max redeemable will be slightly larger than this value
    //this is just a quick estimate
    function getMaxRedeemable(address _pair) external view returns(uint256){
        (, , , IResupplyPair.VaultAccount memory _totalBorrow) = IResupplyPair(_pair).previewAddInterest();
        uint256 minimumLeftover = IResupplyPair(_pair).minimumLeftoverAssets();
        return _totalBorrow.amount - minimumLeftover;
    }

    function getRedemptionFee(address _pair, uint256 _amount) public view returns(uint256){
        return baseRedemptionFee;
    }

    //a basic redemption
    //pull tokens and call redeem on the pair
    function redeem (
        address _pair,
        uint256 _amount,
        uint256 _maxFee,
        address _returnTo
    ) external returns(uint256){
        //pull redeeming tokens
        IERC20(redemptionToken).safeTransferFrom(msg.sender, address(this), _amount);

        //get fee
        uint256 fee = getRedemptionFee(_pair, _amount);
        //check against maxfee to avoid frontrun
        require(fee <= _maxFee,"over max fee");

        //redeem
        return IResupplyPair(_pair).redeem(_amount, fee, _returnTo);
    }

}