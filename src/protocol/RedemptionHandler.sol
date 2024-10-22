// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { CoreOwnable } from '../dependencies/CoreOwnable.sol';
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "../libraries/SafeERC20.sol";
import { IPairRegistry } from "../interfaces/IPairRegistry.sol";
import { IFraxlendPair } from "../interfaces/IFraxlendPair.sol";


//Contract that interacts with pairs to perform redemptions
//Can swap out this contract for another to change logic on how redemption fees are calculated.
//for example can give fee discounts based on certain conditions (like utilization) to
//incentivize redemptions across multiple pools etc
contract RedemptionHandler is CoreOwnable{
    using SafeERC20 for IERC20;

    address public immutable registry;
    address public immutable redemptionToken;

    uint256 public baseRedemptionFee;

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

    //a basic redemption
    //pull tokens and call redeem on the pair
    function redeem (
        address _pair,
        uint256 _amount,
        address _returnTo
    ) external returns(uint256){
        //pull redeeming tokens
        IERC20(redemptionToken).safeTransferFrom(msg.sender, address(this), _amount);
        //redeem
        return IFraxlendPair(_pair).redeem(_amount, baseRedemptionFee, _returnTo);
    }

}