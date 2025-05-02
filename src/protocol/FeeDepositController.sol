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
        uint80 insurance;
        uint80 treasury;
        uint80 platform;
    }

    event SplitsSet(uint80 insurance, uint80 treasury, uint80 platform);

    constructor(
        address _core,
        address _registry,
        uint256 _insuranceSplit, 
        uint256 _treasurySplit
    ) CoreOwnable(_core){
        registry = _registry;
        feeToken = IResupplyRegistry(_registry).token();
        require(_insuranceSplit + _treasurySplit <= BPS, "invalid splits");
        splits.insurance = uint80(_insuranceSplit);
        splits.treasury = uint80(_treasurySplit);
        splits.platform = uint80(BPS - splits.insurance - splits.treasury);
        emit SplitsSet(uint80(_insuranceSplit), uint80(_treasurySplit), splits.platform);
    }

    function distribute() external{
        // Pull fees. Reverts when called multiple times in single epoch.
        address feeDeposit = IResupplyRegistry(registry).feeDeposit();
        IFeeDeposit(feeDeposit).distributeFees();
        uint256 balance = IERC20(feeToken).balanceOf(address(this));
        Splits memory _splits = splits;
        uint256 ipAmount =  balance * _splits.insurance / BPS;
        uint256 treasuryAmount =  balance * _splits.treasury / BPS;
        address treasury = IResupplyRegistry(registry).treasury();
        IERC20(feeToken).safeTransfer(treasury, treasuryAmount);
        address rewardHandler = IResupplyRegistry(registry).rewardHandler();
        IERC20(feeToken).safeTransfer(rewardHandler, ipAmount);
        IRewardHandler(rewardHandler).queueInsuranceRewards();
        IERC20(feeToken).safeTransfer(rewardHandler, balance - ipAmount - treasuryAmount);
        IRewardHandler(rewardHandler).queueStakingRewards();
    }

    /// @notice The ```setSplits``` function sets the fee distribution splits between insurance, treasury, and platform
    /// @param _insuranceSplit The percentage (in BPS) to send to insurance pool
    /// @param _treasurySplit The percentage (in BPS) to send to treasury
    /// @param _platformSplit The percentage (in BPS) to send to platform stakers
    function setSplits(uint256 _insuranceSplit, uint256 _treasurySplit, uint256 _platformSplit) external onlyOwner {
        require(_insuranceSplit + _treasurySplit + _platformSplit == BPS, "invalid splits");
        splits.insurance = uint80(_insuranceSplit);
        splits.treasury = uint80(_treasurySplit);
        splits.platform = uint80(_platformSplit);
        emit SplitsSet(uint80(_insuranceSplit), uint80(_treasurySplit), uint80(_platformSplit));
    }
}