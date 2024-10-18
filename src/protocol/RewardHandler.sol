// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import { SafeERC20 } from "../libraries/SafeERC20.sol";
// import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IPairRegistry } from "../interfaces/IPairRegistry.sol";
import { IFraxlendPair } from "../interfaces/IFraxlendPair.sol";
import { IConvexStaking } from "../interfaces/IConvexStaking.sol";


//claim rewards for various contracts
contract RewardHandler{
    // using SafeERC20 for IERC20;

    address public immutable registry;
    address public immutable insurancepool;
    address public immutable pairEmissions;
    address public immutable insuranceEmissions;

    constructor(address _owner, address _registry, address _insurancepool, address _pairEmissions, address _insuranceEmissions){
        registry = _registry;
        insurancepool = _insurancepool;
        pairEmissions = _pairEmissions;
        insuranceEmissions = _insuranceEmissions;
    }

    function checkNewRewards(address _pair) external{
        address booster = IFraxlendPair(_pair).convexBooster();
        uint256 pid = IFraxlendPair(_pair).convexPid();
        
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
            uint256 rewardSlot = IFraxlendPair(_pair).rewardMap(rtoken);
            if(rewardSlot == 0){
                //a non registered reward
                IFraxlendPair(_pair).addExtraReward(rtoken);
            }

            unchecked{i+=1;}
        }
    }

    function claimRewards(address _pair) external{
        //claim convex staking
        uint256 pid = IFraxlendPair(_pair).convexPid();
        if(pid != 0){
            address booster = IFraxlendPair(_pair).convexBooster();
            (,,,address rewards,,) = IConvexStaking(booster).poolInfo(pid);
            IConvexStaking(rewards).getReward(_pair, true);
        }

        //claim emissions
        //TODO
    }

    function claimInsuranceRewards() external{
        //claim emissions
        //TODO
    }
}