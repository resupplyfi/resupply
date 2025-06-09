// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "../libraries/SafeERC20.sol";
import { IResupplyRegistry } from "../interfaces/IResupplyRegistry.sol";
import { IRewardHandler } from "../interfaces/IRewardHandler.sol";
import { IFeeDeposit } from "../interfaces/IFeeDeposit.sol";
import { CoreOwnable } from "../dependencies/CoreOwnable.sol";

contract FeeDepositController is CoreOwnable{
    using SafeERC20 for IERC20;

    address public immutable registry;
    address public immutable feeToken;
    uint256 public constant BPS = 10_000;
    Splits public splits;

    struct Splits {
        uint40 insurance;
        uint40 treasury;
        uint40 platform;
        uint40 stakedStable;
    }

    event SplitsSet(uint40 insurance, uint40 treasury, uint40 platform, uint40 stakedStable);

    constructor(
        address _core,
        address _registry,
        uint256 _insuranceSplit,
        uint256 _treasurySplit,
        uint256 _stakedStableSplit
    ) CoreOwnable(_core){
        registry = _registry;
        feeToken = IResupplyRegistry(_registry).token();
        require(_insuranceSplit + _treasurySplit <= BPS, "invalid splits");
        splits.insurance = uint40(_insuranceSplit);
        splits.treasury = uint40(_treasurySplit);
        splits.stakedStable = uint40(_stakedStableSplit);
        splits.platform = uint40(BPS - splits.insurance - splits.treasury - splits.stakedStable);
        emit SplitsSet(uint40(_insuranceSplit), uint40(_treasurySplit), splits.platform, uint40(_stakedStableSplit));
    }

    function distribute() external{
        // Pull fees. Reverts when called multiple times in single epoch.
        address feeDeposit = IResupplyRegistry(registry).feeDeposit();
        IFeeDeposit(feeDeposit).distributeFees();
        uint256 balance = IERC20(feeToken).balanceOf(address(this));
        Splits memory _splits = splits;
        uint256 ipAmount =  balance * _splits.insurance / BPS;
        uint256 treasuryAmount =  balance * _splits.treasury / BPS;
        uint256 stakedStableAmount =  balance * _splits.stakedStable / BPS;
        
        //treasury
        address treasury = IResupplyRegistry(registry).treasury();
        IERC20(feeToken).safeTransfer(treasury, treasuryAmount);

        //staked stable
        address staked = IResupplyRegistry(registry).getAddress("SREUSD");
        IERC20(feeToken).safeTransfer(staked, stakedStableAmount);

        //insurance
        address rewardHandler = IResupplyRegistry(registry).rewardHandler();
        IERC20(feeToken).safeTransfer(rewardHandler, ipAmount);
        IRewardHandler(rewardHandler).queueInsuranceRewards();

        //rsup
        IERC20(feeToken).safeTransfer(rewardHandler, balance - ipAmount - treasuryAmount - stakedStableAmount);
        IRewardHandler(rewardHandler).queueStakingRewards();
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