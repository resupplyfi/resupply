// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "../libraries/SafeERC20.sol";
import { IResupplyRegistry } from "../interfaces/IResupplyRegistry.sol";
import { IRewardHandler } from "../interfaces/IRewardHandler.sol";
import { IPriceWatcher } from "../interfaces/IPriceWatcher.sol";
import { IFeeDeposit } from "../interfaces/IFeeDeposit.sol";
import { CoreOwnable } from "../dependencies/CoreOwnable.sol";
import { EpochTracker } from 'src/dependencies/EpochTracker.sol';
import { IFeeLogger } from "../interfaces/IFeeLogger.sol";

contract FeeDepositController is CoreOwnable, EpochTracker{
    using SafeERC20 for IERC20;

    address public immutable registry;
    address public immutable feeToken;
    address public immutable priceWatcher;
    uint256 public maxAdditionalFeeRatio;
    uint256 public constant BPS = 10_000;
    Splits public splits;
    IFeeLogger public immutable feeLogger;
    
    struct WeightData{
        uint64 index;
        uint64 timestamp;
        uint128 avgWeighting;
    }
    mapping(uint256 => WeightData) public epochWeighting;

    struct Splits {
        uint40 insurance;
        uint40 treasury;
        uint40 platform;
        uint40 stakedStable;
    }

    event SplitsSet(uint40 insurance, uint40 treasury, uint40 platform, uint40 stakedStable);
    event MaxAdditionalFeeRatioSet(uint256 ratio);

    /**
     * @param _core Core contract address
     * @param _registry Registry contract address
     * @param _maxAdditionalFee Cap on the amount of additional fees to direct to staked stable (1e6 = 100%)
     * @param _insuranceSplit Insurance split percentage (in BPS)
     * @param _treasurySplit Treasury split percentage (in BPS)
     * @param _stakedStableSplit Staked stable split percentage (in BPS)
     */
    constructor(
        address _core,
        address _registry,
        uint256 _maxAdditionalFee,
        uint256 _insuranceSplit,
        uint256 _treasurySplit,
        uint256 _stakedStableSplit
    ) CoreOwnable(_core) EpochTracker(_core){
        registry = _registry;
        feeToken = IResupplyRegistry(_registry).token();
        priceWatcher = IResupplyRegistry(_registry).getAddress("PRICE_WATCHER");
        feeLogger = IFeeLogger(IResupplyRegistry(_registry).getAddress("FEE_LOGGER"));
        require(_insuranceSplit + _treasurySplit <= BPS, "invalid splits");
        splits.insurance = uint40(_insuranceSplit);
        splits.treasury = uint40(_treasurySplit);
        splits.stakedStable = uint40(_stakedStableSplit);
        splits.platform = uint40(BPS - splits.insurance - splits.treasury - splits.stakedStable);
        emit SplitsSet(uint40(_insuranceSplit), uint40(_treasurySplit), splits.platform, uint40(_stakedStableSplit));

        require(_maxAdditionalFee <= 1e6, "invalid ratio");
        maxAdditionalFeeRatio = _maxAdditionalFee;
        emit MaxAdditionalFeeRatioSet(_maxAdditionalFee);
    }

    function distribute() external{
        // Pull fees. Reverts when called multiple times in single epoch.
        address feeDeposit = IResupplyRegistry(registry).feeDeposit();
        IFeeDeposit(feeDeposit).distributeFees();
        uint256 currentEpoch = getEpoch();
        if(currentEpoch < 2) return;

        uint256 balance = IERC20(feeToken).balanceOf(address(this));

        //log TOTAL fees for current epoch - 2 since the balance here is what was accrued two epochs ago
        feeLogger.logTotalFees(currentEpoch-2, balance);

        //max sure price watcher is up to date
        IPriceWatcher(priceWatcher).updatePriceData();

        uint256 stakedStableAmount;

        //process weighted fees for sreusd

        //first need to look at weighting differences for currentEpoch-2 (which was logged at the beginning of epoch-1)
        //and currentEpoch-1 (which is logged now but the data being logged is for the previous epoch)
        //ex. if getEpoch is 2, we need to find and record the avg weight during epoch 1.
        //we do that by looking at difference of (x-2) and (x-1), aka epoch 0 and 1
        WeightData memory prevWeight = epochWeighting[currentEpoch - 2];
        WeightData memory currentWeight;

        uint256 latestIndex =  IPriceWatcher(priceWatcher).priceDataLength() - 1;

        //only calc if there is enough data to do so, the first execution will result in 0 avgWeighting
        if(prevWeight.index > 0){
            //offset by the timestamp of the previous distribution
            IPriceWatcher.PriceData memory prevData = IPriceWatcher(priceWatcher).priceDataAtIndex(prevWeight.index);
            uint64 dt = prevWeight.timestamp - prevData.timestamp;
            prevData.timestamp = prevData.timestamp + dt;
            prevData.totalWeight = prevData.totalWeight + (prevData.weight * dt);


            //get latest data and extrapolate a new data point that uses latest's weight and the time difference between
            //latest and block.timestamp 
            IPriceWatcher.PriceData memory latest = IPriceWatcher(priceWatcher).priceDataAtIndex(latestIndex);
            dt = uint64(block.timestamp) - latest.timestamp;
            latest.timestamp = latest.timestamp + dt;
            latest.totalWeight = latest.totalWeight + (latest.weight * dt);

            //get difference of total weight between these two points
            uint256 dw = latest.totalWeight - prevData.totalWeight;
            //dt will always be > 0
            dt = latest.timestamp - prevData.timestamp;
            currentWeight.avgWeighting = uint128(dw / dt);
        }

        //set the latest timestamp and index used
        currentWeight.timestamp = uint64(block.timestamp);
        currentWeight.index = uint64(latestIndex);

        //write to state to be used in the following epoch
        epochWeighting[currentEpoch - 1] = currentWeight;

        //next calculate how much of the current balance should be sent to sreusd
        //using currentEpoch - 2 as pair interest is trailing by two epochs

        WeightData memory distroWeight = epochWeighting[currentEpoch - 2];
        if(distroWeight.avgWeighting > 0){
            //get total amount of fees collected in interest only
            uint256 feesInInterest = feeLogger.epochInterestFees(currentEpoch-2);
            //use weighting to determine how much of the max fee should be applied
            uint256 additionalFeeRatio = maxAdditionalFeeRatio * distroWeight.avgWeighting / 1e6;
            additionalFeeRatio = 1e6 + additionalFeeRatio; //turn something like 10% or 0.1 to 1.1
            stakedStableAmount = feesInInterest - (feesInInterest * 1e6 / additionalFeeRatio);
            balance -= stakedStableAmount;
        }

        Splits memory _splits = splits;
        uint256 ipAmount =  balance * _splits.insurance / BPS;
        uint256 treasuryAmount =  balance * _splits.treasury / BPS;
        stakedStableAmount +=  balance * _splits.stakedStable / BPS;
        
        //treasury
        address treasury = IResupplyRegistry(registry).treasury();
        IERC20(feeToken).safeTransfer(treasury, treasuryAmount);

        //staked stable
        address staked = IResupplyRegistry(registry).getAddress("SREUSD");
        IERC20(feeToken).safeTransfer(staked, stakedStableAmount);

        //insurance pool
        address rewardHandler = IResupplyRegistry(registry).rewardHandler();
        IERC20(feeToken).safeTransfer(rewardHandler, ipAmount);
        IRewardHandler(rewardHandler).queueInsuranceRewards();

        //rsup stakers
        IERC20(feeToken).safeTransfer(rewardHandler, balance - ipAmount - treasuryAmount - stakedStableAmount);
        IRewardHandler(rewardHandler).queueStakingRewards();
    }

    /// @notice The ```setMaxAdditionalFeeRatio``` function sets the max additional fee ratio attributed to staked stable
    /// @param _maxAdditionalFee max additional fee ratio (1e6 = 100%)
    function setMaxAdditionalFeeRatio(uint256 _maxAdditionalFee) external onlyOwner {
        require(_maxAdditionalFee <= 1e6, "invalid ratio");
        maxAdditionalFeeRatio = _maxAdditionalFee;
        emit MaxAdditionalFeeRatioSet(_maxAdditionalFee);
    }

    /// @notice The ```setSplits``` function sets the fee distribution splits between insurance, treasury, and platform
    /// @param _insuranceSplit The percentage (in BPS) to send to insurance pool
    /// @param _treasurySplit The percentage (in BPS) to send to treasury
    /// @param _platformSplit The percentage (in BPS) to send to platform stakers
    function setSplits(uint256 _insuranceSplit, uint256 _treasurySplit, uint256 _platformSplit, uint256 _stakedStableSplit) external onlyOwner {
        require(_insuranceSplit + _treasurySplit + _platformSplit == BPS, "invalid splits");
        splits.insurance = uint40(_insuranceSplit);
        splits.treasury = uint40(_treasurySplit);
        splits.platform = uint40(_platformSplit);
        splits.stakedStable = uint40(_stakedStableSplit);
        emit SplitsSet(uint40(_insuranceSplit), uint40(_treasurySplit), uint40(_platformSplit), uint40(_stakedStableSplit));
    }
}