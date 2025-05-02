// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { console } from "lib/forge-std/src/console.sol";
import { ResupplyPair } from "src/protocol/ResupplyPair.sol";
import { RewardDistributorMultiEpoch } from "src/protocol/RewardDistributorMultiEpoch.sol";
import { Setup } from "test/Setup.sol";
import { PairTestBase } from "./PairTestBase.t.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract PairTestFeeFlow is PairTestBase {
    function setUp() public override {
        super.setUp();
    }

    /*
    queue up fees on pair
    distro fee deposit
    queue up new fees
    distro next week fee deposit

    check gov token staking token rates
    check insurance pool token rates
    check treasury token amount
    check pair weightings
    check pair emission rates
    check pair earned()
    */
    function test_feeFlow() public {
        assertEq(pair.userCollateralBalance(_THIS), 0);

        deal(address(stakingToken), address(this), 1e18);
        stakingToken.approve(address(staker), 1e18);
        staker.stake(address(this), 1e18);
        assertEq(staker.balanceOf(_THIS), 1e18);

        printPairFees(pair);
        skip(feeDeposit.epochLength());
        printPairFees(pair);
        feeDepositController.distribute();
        pair.withdrawFees();

        uint256 maxltv = pair.maxLTV();
        uint256 availableDebt = pair.totalDebtAvailable();
        (,,uint256 exchangeRate) = pair.exchangeRateInfo();

        uint256 collateralAmount = getCollateralAmount(availableDebt,exchangeRate,maxltv);
        deal(address(collateral), address(this), collateralAmount);

        pair.addCollateralVault(collateralAmount, address(this));
        borrow(pair, availableDebt, 0);
        console.log("\nborrowed\n");
        assertEq(pair.userCollateralBalance(_THIS), collateralAmount);


        vm.warp(block.timestamp +7 days);
        pair.addInterest(false);

        (uint256 userborrowshares, uint256 usercollateral) = pair.getUserSnapshot(address(this));
        (uint256 claimblefees, uint128 totalBorrowAmount, uint128 totalborrowShares, uint256 totalCollateral) = pair.getPairAccounting();

        console.log("userborrowshares: ", userborrowshares);
        console.log("usercollateral: ", usercollateral);
        console.log("claimblefees: ", claimblefees);
        console.log("totalBorrowAmount: ", totalBorrowAmount);
        console.log("totalborrowShares: ", totalborrowShares);
        console.log("totalCollateral: ", totalCollateral);

        printPairFees(pair);
        printDistributionInfo();
        feeDepositController.distribute();
        pair.withdrawFees();
        console.log("\nclaimed fees\n");
        printPairFees(pair);
        printDistributionInfo();

        console.log("\nwarp to next week now that these are queued\n");

        skip(feeDeposit.epochLength());
        pair.addInterest(false);

        printPairFees(pair);
        printDistributionInfo();
        feeDepositController.distribute();
        pair.withdrawFees();
        console.log("\nclaimed fees\n");
        printPairFees(pair);
        printDistributionInfo();

        vm.warp(block.timestamp +1 days);
        console.log("\nwarp to check claimables\n");
        printDistributionInfo();

        RewardDistributorMultiEpoch.EarnedData[] memory earnedData = pair.earned(address(this));
        console.log("govToken rewards before claim: ", stakingToken.balanceOf(address(this)));
        pair.getReward(address(this));
        console.log("govToken rewards after claim: ", stakingToken.balanceOf(address(this)));

        //the claimable amount should equal what was actually claimed
        assertEq(earnedData[0].amount, stakingToken.balanceOf(address(this)));
    }

    function test_insurancePoolFees() public {
        assertEq(pair.userCollateralBalance(_THIS), 0);

        deal(address(stakingToken), address(this), 1e18);
        stakingToken.approve(address(staker), 1e18);
        staker.stake(address(this), 1e18);
        assertEq(staker.balanceOf(_THIS), 1e18);

        deal(address(stablecoin), address(this), 2e18);
        stablecoin.approve(address(insurancePool), 9999e18);
        insurancePool.deposit(1e18, address(this));
        assertEq(insurancePool.balanceOf(_THIS), 1e18);

        console.log("assets in IP: ", insurancePool.convertToAssets(insurancePool.balanceOf(_THIS)));

        skip(feeDeposit.epochLength());
        feeDepositController.distribute();
        pair.withdrawFees();

        uint256 maxltv = pair.maxLTV();
        uint256 availableDebt = pair.totalDebtAvailable();
        (,,uint256 exchangeRate) = pair.exchangeRateInfo();

        uint256 collateralAmount = getCollateralAmount(availableDebt,exchangeRate,maxltv);
        deal(address(collateral), address(this), collateralAmount);

        pair.addCollateralVault(collateralAmount, address(this));
        borrow(pair, availableDebt, 0);
        console.log("\nborrowed\n");
        assertEq(pair.userCollateralBalance(_THIS), collateralAmount);
        

        uint startEpoch = feeDeposit.getEpoch();
        skip(feeDeposit.epochLength());
        console.log("start epoch: ", startEpoch);
        console.log("end epoch: ", feeDeposit.getEpoch());
        pair.addInterest(false);

       // printPairFees(pair);
       // printDistributionInfo();
        feeDepositController.distribute();
        pair.withdrawFees();
        console.log("\nclaimed fees\n");
        //printPairFees(pair);
        //printDistributionInfo();

        console.log("\nwarp to next week now that these are queued\n");

        skip(feeDeposit.epochLength());
        pair.addInterest(false);

        // printPairFees(pair);
        // printDistributionInfo();
        feeDepositController.distribute();
        pair.withdrawFees();
        console.log("\nclaimed fees\n");
        printPairFees(pair);
        printDistributionInfo();

        skip(feeDeposit.epochLength());
        console.log("\nwarp to check claimables\n");
        console.log("assets in IP: ", insurancePool.convertToAssets(insurancePool.balanceOf(_THIS)));
        console.log("govToken on insurance: ", stakingToken.balanceOf(address(insurancePool)));
        RewardDistributorMultiEpoch.EarnedData[] memory earnedData = insurancePool.earned(address(this));
        uint256 rlength =  earnedData.length;
        for(uint256 i = 0; i < rlength; i++){
            console.log("insurance rewards this-> earned token: ", earnedData[i].token, ", amount: ", earnedData[i].amount);
        }
        earnedData = insurancePool.earned(address(insurancePool));
        for(uint256 i = 0; i < rlength; i++){
            console.log("insurance rewards burnt-> earned token: ", earnedData[i].token, ", amount: ", earnedData[i].amount);
        }
        console.log("assets in IP: ", insurancePool.convertToAssets(insurancePool.balanceOf(_THIS)));
        console.log("govToken on insurance: ", stakingToken.balanceOf(address(insurancePool)));

        //check withdraw
        console.log("govToken on this: ", stakingToken.balanceOf(address(this)));
        insurancePool.exit();
        console.log("govToken on this after exit: ", stakingToken.balanceOf(address(this)));
        earnedData = insurancePool.earned(address(this));
        for(uint256 i = 0; i < rlength; i++){
            console.log("insurance rewards this-> earned token: ", earnedData[i].token, ", amount: ", earnedData[i].amount);
        }
        earnedData = insurancePool.earned(address(insurancePool));
        for(uint256 i = 0; i < rlength; i++){
            console.log("insurance rewards burnt-> earned token: ", earnedData[i].token, ", amount: ", earnedData[i].amount);
        }
        skip(1 days);
        console.log("\nwarp to check claimables\n");
        earnedData = insurancePool.earned(address(this));
        for(uint256 i = 0; i < rlength; i++){
            console.log("insurance rewards this-> earned token: ", earnedData[i].token, ", amount: ", earnedData[i].amount);
        }
        earnedData = insurancePool.earned(address(insurancePool));
        for(uint256 i = 0; i < rlength; i++){
            console.log("insurance rewards burnt-> earned token: ", earnedData[i].token, ", amount: ", earnedData[i].amount);
        }

        skip(6 days);
        feeDepositController.distribute();
        pair.withdrawFees();
        // insurancePool.getReward(address(this));

        insurancePool.redeem(insurancePool.balanceOf(address(this))/2, address(this), address(this));
        console.log("\nredeemed half\n");
        console.log("assets in IP: ", insurancePool.convertToAssets(insurancePool.balanceOf(_THIS)));
        
        skip(1 days);
        console.log("\nwarp to check claimables\n");
        console.log("govToken on this: ", stakingToken.balanceOf(address(this)));
        earnedData = insurancePool.earned(address(this));
        for(uint256 i = 0; i < rlength; i++){
            console.log("insurance rewards this-> earned token: ", earnedData[i].token, ", amount: ", earnedData[i].amount);
        }
        earnedData = insurancePool.earned(address(insurancePool));
        for(uint256 i = 0; i < rlength; i++){
            console.log("insurance rewards burnt-> earned token: ", earnedData[i].token, ", amount: ", earnedData[i].amount);
        }
        insurancePool.getReward(address(this));
        console.log("govToken on this: ", stakingToken.balanceOf(address(this)));
        earnedData = insurancePool.earned(address(this));
        for(uint256 i = 0; i < rlength; i++){
            console.log("insurance rewards this-> earned token: ", earnedData[i].token, ", amount: ", earnedData[i].amount);
        }

        insurancePool.exit();
        console.log("\nexit started\n");
        skip(1 days);
        console.log("\nwarp ahead, no new emissions should be claimable\n");
        //expect revert
        uint256 redeembalance = insurancePool.balanceOf(address(this));
        vm.expectRevert("!withdraw time");
        insurancePool.redeem(redeembalance, address(this), address(this));
        //expect revert
        vm.expectRevert("withdraw queued");
        insurancePool.deposit(1e18, address(this));

        earnedData = insurancePool.earned(address(this));
        for(uint256 i = 0; i < rlength; i++){
            console.log("insurance rewards this-> earned token: ", earnedData[i].token, ", amount: ", earnedData[i].amount);
        }
        earnedData = insurancePool.earned(address(insurancePool));
        for(uint256 i = 0; i < rlength; i++){
            console.log("insurance rewards burnt-> earned token: ", earnedData[i].token, ", amount: ", earnedData[i].amount);
        }

        console.log("withdraw queue: ", insurancePool.withdrawQueue(address(this)));
        insurancePool.cancelExit();
        console.log("\nexit canceled, new emissions can be claimed now but not ones during exit\n");
        console.log("withdraw queue: ", insurancePool.withdrawQueue(address(this)));

        earnedData = insurancePool.earned(address(this));
        for(uint256 i = 0; i < rlength; i++){
            console.log("insurance rewards this-> earned token: ", earnedData[i].token, ", amount: ", earnedData[i].amount);
        }
        earnedData = insurancePool.earned(address(insurancePool));
        for(uint256 i = 0; i < rlength; i++){
            console.log("insurance rewards burnt-> earned token: ", earnedData[i].token, ", amount: ", earnedData[i].amount);
        }
        skip(1 days);
        console.log("\nwarp to check claimables\n");

        earnedData = insurancePool.earned(address(this));
        for(uint256 i = 0; i < rlength; i++){
            console.log("insurance rewards this-> earned token: ", earnedData[i].token, ", amount: ", earnedData[i].amount);
        }
        earnedData = insurancePool.earned(address(insurancePool));
        for(uint256 i = 0; i < rlength; i++){
            console.log("insurance rewards burnt-> earned token: ", earnedData[i].token, ", amount: ", earnedData[i].amount);
        }

        console.log("withdraw queue: ", insurancePool.withdrawQueue(address(this)));
        console.log("final withdraw");
        vm.expectRevert("!withdraw time");
        insurancePool.redeem(redeembalance, address(this), address(this));

        insurancePool.exit();
        skip(10 days);
        vm.expectRevert("withdraw time over");
        insurancePool.redeem(redeembalance, address(this), address(this));

        insurancePool.exit();
        skip(8 days);
        insurancePool.redeem(redeembalance, address(this), address(this));
    }

    function printDistributionInfo() internal{
        console.log("stables on feeDeposit: ", stablecoin.balanceOf(address(feeDeposit)));
        console.log("stables on gov staker: ", stablecoin.balanceOf(address(staker)));
        console.log("stables on treasury: ", stablecoin.balanceOf(address(treasury)));
        console.log("stables on insurance: ", stablecoin.balanceOf(address(insurancePool)));
        console.log("stables on insurance distribution: ", stablecoin.balanceOf(address(ipStableStream)));
        console.log("govToken on insurance: ", stakingToken.balanceOf(address(insurancePool)));
        console.log("govToken on insurance distribution: ", stakingToken.balanceOf(address(ipEmissionStream)));
        console.log("govToken on pair emissions: ", stakingToken.balanceOf(address(pairEmissionStream)));
        console.log("govToken on pair: ", stakingToken.balanceOf(address(pair)));

        (,,,uint256 rate,,) = staker.rewardData(address(stablecoin));
        console.log("stables reward rate on gov staker: ",rate);
        console.log("stables reward rate on insurancepool: ", ipStableStream.rewardRate());
        console.log("emission reward rate on insurancepool: ", ipEmissionStream.rewardRate());
        console.log("emission reward rate for all pairs: ", pairEmissionStream.rewardRate());
        console.log("weight of current pair: ", pairEmissionStream.balanceOf(address(pair)));
        console.log("total pair weight: ", pairEmissionStream.totalSupply());
        console.log("emissions earned by pair: ", pairEmissionStream.earned(address(pair)));
        RewardDistributorMultiEpoch.EarnedData[] memory earnedData = pair.earned(address(this));
        uint256 rlength =  earnedData.length;
        for(uint256 i = 0; i < rlength; i++){
            console.log("borrow rewards -> earned token: ", earnedData[i].token, ", amount: ", earnedData[i].amount);
        }
        //earned should have claimed all emissions for the pair
       assertEq(pairEmissionStream.earned(address(pair)), 0);
    }
}
