// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "../libraries/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IPairRegistry } from "../interfaces/IPairRegistry.sol";
import { IRewardHandler } from "../interfaces/IRewardHandler.sol";
import { IFeeDeposit } from "../interfaces/IFeeDeposit.sol";



//FeeDeposit controller to handle distribution of funds
contract FeeDepositController{
    using SafeERC20 for IERC20;

    address public immutable registry;
    address public immutable feeDeposit;
    address public immutable feeToken;

    uint256 public immutable insuranceShare;
    uint256 public constant denominator = 10000;

    constructor(address _registry, address _feeDeposit, address _feeToken, uint256 _insuranceShare){
        registry = _registry;
        feeDeposit = _feeDeposit;
        feeToken = _feeToken;
        insuranceShare = _insuranceShare;
    }

    function distribute() external{
        //pull fees
        IFeeDeposit(feeDeposit).distributeFees();
        
        uint256 balance = IERC20(feeToken).balanceOf(address(this));
        //insurance pool amount
        uint256 ipAmount =  balance * insuranceShare / denominator;

        address rewardHandler = IPairRegistry(registry).rewardHandler();
        //send to handler
        IERC20(feeToken).safeTransfer(rewardHandler, ipAmount);
        //process insurance rewards
        IRewardHandler(rewardHandler).queueInsuranceRewards();

        //send rest to platform (via reward handler again)
        IERC20(feeToken).safeTransfer(rewardHandler, balance - ipAmount);
        //process platform rewards
        IRewardHandler(rewardHandler).queuePlatformRewards();
        
    }
}