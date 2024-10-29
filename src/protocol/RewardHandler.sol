// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IPairRegistry } from "../interfaces/IPairRegistry.sol";
import { IResupplyPair } from "../interfaces/IResupplyPair.sol";
import { IConvexStaking } from "../interfaces/IConvexStaking.sol";
import { IRewards } from "../interfaces/IRewards.sol";
import { IRewardHandler } from "../interfaces/IRewardHandler.sol";
import { IFeeDeposit } from "../interfaces/IFeeDeposit.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "../libraries/SafeERC20.sol";


//claim rewards for various contracts
contract RewardHandler{
    using SafeERC20 for IERC20;

    address public immutable registry;
    address public immutable revenueToken;
    address public immutable insurancepool;
    address public immutable pairEmissions;
    address public immutable insuranceEmissions;
    address public immutable insuranceRevenue;
    address public immutable platformRewards;

    mapping(address => uint256) public pairTimestamp;

    constructor(address _owner, address _registry, address _revenueToken, address _platformRewards, address _insurancepool, address _pairEmissions, address _insuranceEmissions, address _insuranceRevenue){
        registry = _registry;
        revenueToken = _revenueToken;
        platformRewards = _platformRewards;
        insurancepool = _insurancepool;
        pairEmissions = _pairEmissions;
        insuranceEmissions = _insuranceEmissions;
        insuranceRevenue = _insuranceRevenue;
        IERC20(_insuranceRevenue).approve(_revenueToken, type(uint256).max);
        IERC20(_platformRewards).approve(_revenueToken, type(uint256).max);
    }

    function checkNewRewards(address _pair) external{
        address booster = IResupplyPair(_pair).convexBooster();
        uint256 pid = IResupplyPair(_pair).convexPid();
        
        //get main reward distribution contract from convex pool
        (,,,address rewards,,) = IConvexStaking(booster).poolInfo(pid);

        uint256 rewardLength = IConvexStaking(rewards).extraRewardsLength();

        for(uint256 i=0; i < rewardLength;){
            //get extra reward distribution contract from convex pool
            address rtoken = IConvexStaking(rewards).extraRewards(i);
            //get distributing wrapped token
            rtoken = IConvexStaking(rtoken).rewardToken();
            //get the actual token
            rtoken = IConvexStaking(rtoken).token();

            //get reward index on the pair for the given token
            uint256 rewardSlot = IResupplyPair(_pair).rewardMap(rtoken);
            if(rewardSlot == 0){
                //a non registered reward
                IResupplyPair(_pair).addExtraReward(rtoken);
            }

            unchecked{i+=1;}
        }
    }

    function claimRewards(address _pair) external{
        //claim convex staking
        uint256 pid = IResupplyPair(_pair).convexPid();
        if(pid != 0){
            address booster = IResupplyPair(_pair).convexBooster();
            (,,,address rewards,,) = IConvexStaking(booster).poolInfo(pid);
            IConvexStaking(rewards).getReward(_pair, true);
        }

        //claim emissions
        IRewards(pairEmissions).getReward(_pair);
    }

    function claimInsuranceRewards() external{
        //claim revenue share
        IRewards(insuranceRevenue).getReward(insurancepool);
        
        //claim emissions
        IRewards(insuranceEmissions).getReward(insurancepool);
    }

    function setPairWeight(address _pair, uint256 _amount) external{
        require(msg.sender == IPairRegistry(registry).feeDeposit(), "!feeDeposist");

        //get previous and update
        uint256 lastTimestamp = pairTimestamp[_pair];
        pairTimestamp[_pair] == block.timestamp;

        //if first record, assume 7 days
        if(lastTimestamp == 0){            
            lastTimestamp = block.timestamp - 7 days;
        }

        //convert amount to amount per second. (precision loss ok as its just weights)
        uint256 rate = block.timestamp - lastTimestamp;
        rate = _amount / rate;

        IRewards(pairEmissions).setWeight(msg.sender, _amount);
    }

    function queueInsuranceRewards() external{
        //check that caller is feedeposit or operator of fee deposit
        address feeDeposit = IPairRegistry(registry).feeDeposit();
        require(msg.sender == feeDeposit || msg.sender == IFeeDeposit(feeDeposit).operator(), "!feeDeposist");

        //queue up any reward tokens currently on this handler
        IRewards(insuranceRevenue).queueNewRewards(IERC20(revenueToken).balanceOf(address(this)));
    }

    function queuePlatformRewards() external{
        //check that caller is feedeposit or operator of fee deposit
        address feeDeposit = IPairRegistry(registry).feeDeposit();
        require(msg.sender == feeDeposit || msg.sender == IFeeDeposit(feeDeposit).operator(), "!feeDeposist");

        //queue up any reward tokens currently on this handler
        IRewards(platformRewards).notifyRewardAmount(revenueToken, IERC20(revenueToken).balanceOf(address(this)));
    }
}