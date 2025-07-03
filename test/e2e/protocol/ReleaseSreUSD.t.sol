// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import { console } from "lib/forge-std/src/console.sol";
import { StakedReUSD } from "src/protocol/sreusd/sreUSD.sol";
import { ERC20, LinearRewardsErc4626 } from "src/protocol/sreusd/LinearRewardsErc4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Setup } from "test/e2e/Setup.sol";
import { FeeDepositController } from "src/protocol/FeeDepositController.sol";
import { FeeLogger } from "src/protocol/FeeLogger.sol";
import { RewardHandler } from "src/protocol/RewardHandler.sol";
import { InterestRateCalculatorV2 } from "src/protocol/InterestRateCalculatorV2.sol";

import { IFeeDepositController } from "src/interfaces/IFeeDepositController.sol";
import { IRewardHandler } from "src/interfaces/IRewardHandler.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";

contract sreUSDTest is Setup {
    StakedReUSD public vault;
    IERC20 public asset;

    uint32 public constant REWARDS_CYCLE_LENGTH = 7 days;
    uint256 public constant MAX_DISTRIBUTION_PER_SECOND_PER_ASSET = 1e18;
    address[] public pairs;

    function setUp() public override {
        super.setUp();
        asset = IERC20(address(stablecoin));
        vault = stakedStable;
        deal(address(govToken), address(user1), 1000e18);
        _makeInitialGovStakerDeposit();
    }

    // TODO: Peg lower
    // TODO: Peg higher
    // TODO: Fee Logger
    // TODO: Interest Rate Calculator

    function _makeInitialGovStakerDeposit() internal {
        deal(address(govToken), address(user1), 1000e18);
        vm.startPrank(address(user1));
        govToken.approve(address(staker), 1000e18);
        staker.stake(1000e18);
        vm.stopPrank();
    }
}