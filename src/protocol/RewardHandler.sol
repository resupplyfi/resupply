// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { CoreOwnable } from '../dependencies/CoreOwnable.sol';
import { IResupplyRegistry } from "../interfaces/IResupplyRegistry.sol";
import { IResupplyPair } from "../interfaces/IResupplyPair.sol";
import { IConvexStaking } from "../interfaces/IConvexStaking.sol";
import { IRewards } from "../interfaces/IRewards.sol";
import { IRewardHandler } from "../interfaces/IRewardHandler.sol";
import { IFeeDeposit } from "../interfaces/IFeeDeposit.sol";
import { ISimpleReceiver } from "../interfaces/ISimpleReceiver.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "../libraries/SafeERC20.sol";
import { EpochTracker } from "../dependencies/EpochTracker.sol";


//claim rewards for various contracts
contract RewardHandler is CoreOwnable, EpochTracker {
    using SafeERC20 for IERC20;

    address public immutable registry;
    address public immutable revenueToken;
    address public immutable insurancepool;
    address public immutable pairEmissions;
    address public immutable insuranceEmissions;
    address public immutable insuranceRevenue;
    address public immutable platformRewards;
    address public immutable emissionReceiver;
    address public immutable emissionToken;

    mapping(address => uint256) public pairTimestamp;
    mapping(address => uint256) public minimumWeights;
    uint256 public baseMinimumWeight;

    event BaseMinimumWeightSet(uint256 bweight);
    event MinimumWeightSet(address indexed user, uint256 mweight);

    constructor(
        address _core, 
        address _registry, 
        address _revenueToken, 
        address _platformRewards, 
        address _insurancepool, 
        address _emissionReceiver, 
        address _pairEmissions, 
        address _insuranceEmissions, 
        address _insuranceRevenue
    ) CoreOwnable(_core) EpochTracker(_core){
        registry = _registry;
        revenueToken = _revenueToken;
        platformRewards = _platformRewards;
        insurancepool = _insurancepool;
        pairEmissions = _pairEmissions;
        insuranceEmissions = _insuranceEmissions;
        insuranceRevenue = _insuranceRevenue;
        emissionReceiver = _emissionReceiver;
        emissionToken = IRewards(pairEmissions).rewardToken();
        IERC20(_revenueToken).approve(_insuranceRevenue, type(uint256).max);
        IERC20(_revenueToken).approve(_platformRewards, type(uint256).max);
        IERC20(emissionToken).approve(pairEmissions, type(uint256).max);
    }

    function setBaseMinimumWeight(uint256 _amount) external onlyOwner{
        baseMinimumWeight = _amount;
        emit BaseMinimumWeightSet(_amount);
    }

    function setPairMinimumWeight(address _account, uint256 _amount) external onlyOwner{
        minimumWeights[_account] = _amount;
        emit MinimumWeightSet(_account, _amount);
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

    /// @notice Claims Relend emissions and external protocol rewards for a given pair
    /// @param _pair The address of the pair to claim rewards for
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
        require(msg.sender == IResupplyRegistry(registry).feeDeposit(), "!feeDeposist");

        //get previous and update
        uint256 lastTimestamp = pairTimestamp[_pair];
        pairTimestamp[_pair] == block.timestamp;

        uint256 borrowLimit = IResupplyPair(_pair).borrowLimit();
        uint256 rate;

        //if borrow limit is 0, dont apply any weight
        if(borrowLimit > 0){

            // if first call for pair use epoch length
            lastTimestamp = lastTimestamp == 0 ? block.timestamp - epochLength : lastTimestamp;

            //convert amount to amount per second. (precision loss ok as its just weights)
            rate = block.timestamp - lastTimestamp;
            rate = _amount / rate;

            //if minimum set check if rate is below
            if(minimumWeights[_pair] != 0 && rate < minimumWeights[_pair]){
                rate = minimumWeights[_pair];
            }else if(rate < baseMinimumWeight){
                //if rate below the global base minimum then clamp
                rate = baseMinimumWeight;
            }
        }
        
        IRewards(pairEmissions).setWeight(_pair, rate);
    }

    function queueInsuranceRewards() external{
        //check that caller is feedeposit or operator of fee deposit
        address feeDeposit = IResupplyRegistry(registry).feeDeposit();
        require(msg.sender == feeDeposit || msg.sender == IFeeDeposit(feeDeposit).operator(), "!feeDeposist");

        //queue up any reward tokens currently on this handler
        IRewards(insuranceRevenue).queueNewRewards(IERC20(revenueToken).balanceOf(address(this)));
    }

    function queuePlatformRewards() external{
        //check that caller is feedeposit or operator of fee deposit
        address feeDeposit = IResupplyRegistry(registry).feeDeposit();
        require(msg.sender == feeDeposit || msg.sender == IFeeDeposit(feeDeposit).operator(), "!feeDeposist");

        //queue up any reward tokens currently on this handler
        IRewards(platformRewards).notifyRewardAmount(revenueToken, IERC20(revenueToken).balanceOf(address(this)));

        //since this should get called once per epoch, can do emission handling as well
        ISimpleReceiver(emissionReceiver).allocateEmissions();
        if(ISimpleReceiver(emissionReceiver).claimableEmissions() > 0){
            ISimpleReceiver(emissionReceiver).claimEmissions(address(this));
            IRewards(pairEmissions).queueNewRewards(IERC20(emissionToken).balanceOf(address(this)));
        }
    }
}