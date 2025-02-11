// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { CoreOwnable } from '../dependencies/CoreOwnable.sol';
import { IResupplyRegistry } from "../interfaces/IResupplyRegistry.sol";
import { IResupplyPair } from "../interfaces/IResupplyPair.sol";
import { IConvexStaking } from "../interfaces/IConvexStaking.sol";
import { IRewards } from "../interfaces/IRewards.sol";
import { IInsurancePool } from "../interfaces/IInsurancePool.sol";
import { IFeeDeposit } from "../interfaces/IFeeDeposit.sol";
import { ISimpleReceiver } from "../interfaces/ISimpleReceiver.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "../libraries/SafeERC20.sol";
import { EpochTracker } from "../dependencies/EpochTracker.sol";
import { IGovStaker } from "../interfaces/IGovStaker.sol";

//claim rewards for various contracts
contract RewardHandler is CoreOwnable, EpochTracker {
    using SafeERC20 for IERC20;

    address public immutable registry;
    address public immutable revenueToken;
    address public immutable insurancepool;
    address public immutable pairEmissions;
    address public immutable insuranceEmissions;
    address public immutable insuranceRevenue;
    address public immutable govStaker;
    address public immutable emissionToken;
    ISimpleReceiver public immutable debtEmissionsReceiver;
    ISimpleReceiver public immutable insuranceEmissionReceiver;

    mapping(address => uint256) public pairTimestamp;
    mapping(address => uint256) public minimumWeights;
    uint256 public baseMinimumWeight;

    event BaseMinimumWeightSet(uint256 bweight);
    event MinimumWeightSet(address indexed user, uint256 mweight);

    constructor(
        address _core, 
        address _registry, 
        address _insurancepool, 
        address _debtEmissionsReceiver, 
        address _pairEmissions, 
        address _insuranceEmissions, 
        address _insuranceRevenue
    ) CoreOwnable(_core) EpochTracker(_core){
        registry = _registry;
        address _revenueToken = IResupplyRegistry(registry).token();
        require(_revenueToken != address(0), "revenueToken not set");
        address _emissionToken = IResupplyRegistry(registry).govToken();
        require(_emissionToken != address(0), "emissionToken not set");
        address _govStaker = IResupplyRegistry(registry).staker();
        require(_govStaker != address(0), "govStaker not set");
        revenueToken = _revenueToken;
        emissionToken = _emissionToken;
        govStaker = _govStaker;
        insurancepool = _insurancepool;
        pairEmissions = _pairEmissions;
        insuranceEmissions = _insuranceEmissions;
        insuranceRevenue = _insuranceRevenue;
        debtEmissionsReceiver = ISimpleReceiver(_debtEmissionsReceiver);
        insuranceEmissionReceiver = ISimpleReceiver(IInsurancePool(insurancepool).emissionsReceiver());

        IERC20(_revenueToken).approve(_insuranceRevenue, type(uint256).max);
        IERC20(_revenueToken).approve(_govStaker, type(uint256).max);
        IERC20(_emissionToken).approve(pairEmissions, type(uint256).max);
        IERC20(_emissionToken).approve(insuranceEmissions, type(uint256).max);
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
        require(pid != 0, "pid cannot be 0");
        
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

    /// @notice Claims emissions and external protocol rewards for a given pair
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
        pairTimestamp[_pair] = block.timestamp;

        uint256 borrowLimit = IResupplyPair(_pair).borrowLimit();
        uint256 rate;

        //if borrow limit is 0, dont apply any weight
        if(borrowLimit > 0){

            // if first call for pair use epoch length
            lastTimestamp = lastTimestamp == 0 ? block.timestamp - epochLength : lastTimestamp;

            //calculate our `rate`, which is just amount per second to be used as weights for fair distribution (precision loss ok)
            rate = _amount / (block.timestamp - lastTimestamp);

            //clamp rate floor to a minimum value
            //use custom pair setting if set, otherwise compare against baseMinimumWeight
            uint256 minWeight = minimumWeights[_pair];
            minWeight = minWeight == 0 ? baseMinimumWeight : minWeight;
            if(rate < minWeight){
                rate = minWeight;
            }
        }
        
        IRewards(pairEmissions).setWeight(_pair, rate);
    }

    function queueInsuranceRewards() external{
        //check that caller is feedeposit or operator of fee deposit
        address feeDeposit = IResupplyRegistry(registry).feeDeposit();
        require(msg.sender == IFeeDeposit(feeDeposit).operator(), "!feeDeposistOp");

        //queue up any reward tokens currently on this handler
        IRewards(insuranceRevenue).queueNewRewards(IERC20(revenueToken).balanceOf(address(this)));

        insuranceEmissionReceiver.allocateEmissions();
        if(insuranceEmissionReceiver.claimableEmissions() > 0){
            insuranceEmissionReceiver.claimEmissions(address(this));
            IRewards(insuranceEmissions).queueNewRewards(IERC20(emissionToken).balanceOf(address(this)));
        }
    }

    function queueStakingRewards() external{
        //check that caller is feedeposit or operator of fee deposit
        address feeDeposit = IResupplyRegistry(registry).feeDeposit();
        require(msg.sender == IFeeDeposit(feeDeposit).operator(), "!feeDeposistOp");

        //queue up any reward tokens currently on this handler
        uint256 revenueBalance = IERC20(revenueToken).balanceOf(address(this));
        if(revenueBalance > 0){
            IGovStaker(govStaker).notifyRewardAmount(revenueToken, revenueBalance);
        }

        //since this should get called once per epoch, can do emission handling as well
        debtEmissionsReceiver.allocateEmissions();
        if(debtEmissionsReceiver.claimableEmissions() > 0){
            debtEmissionsReceiver.claimEmissions(address(this));
            IRewards(pairEmissions).queueNewRewards(IERC20(emissionToken).balanceOf(address(this)));
        }
    }
}