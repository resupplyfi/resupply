// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import { Protocol, Mainnet } from "src/Constants.sol";
import { console } from "lib/forge-std/src/console.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC4626 } from "src/interfaces/IERC4626.sol";
import { Setup } from "test/integration/Setup.sol";
import { CurveLendMinter } from "src/dao/CurveLendMinter.sol";
import { CurveLendMinterFactory } from "src/dao/CurveLendMinterFactory.sol";
import { ICrvusdController } from 'src/interfaces/ICrvusdController.sol';

contract CurveLendMinterTest is Setup {
    
    CurveLendMinterFactory public factory;
    CurveLendMinter public lender;
    ICrvusdController public crvusdController;
    IERC20 public market;
    IERC4626 public marketVault;
    address public feeReceiver;

    function setUp() public override {
        super.setUp();
        
        //deploy implementation and factory
        CurveLendMinter lenderImpl = new CurveLendMinter();

        crvusdController = ICrvusdController(Mainnet.CURVE_CRVUSD_CONTROLLER);
        feeReceiver = crvusdController.fee_receiver();

        factory = new CurveLendMinterFactory(
            Mainnet.CURVE_OWNERSHIP_AGENT,
            address(crvusdController),
            feeReceiver,
            address(lenderImpl)
        );

        market = IERC20(Mainnet.CURVELEND_SREUSD_CRVUSD);
        marketVault = IERC4626(Mainnet.CURVELEND_SREUSD_CRVUSD);

        vm.startPrank(Mainnet.CURVE_OWNERSHIP_AGENT);
        lender = CurveLendMinter(factory.addMarketOperator(address(market)));

        vm.stopPrank();
    }

    function printInfo() private{
        console.log("---------------------------");
        uint256 mintedAmount = lender.mintedAmount();
        uint256 marketShares = market.balanceOf(address(lender));
        uint256 currentAssets = marketVault.convertToAssets(marketShares);
        console.log("factory crvusd balance: ", crvusd.balanceOf(address(factory)));
        console.log("lender crvusd balance: ", crvusd.balanceOf(address(lender)));
        console.log("fee receiver crvusd balance: ", crvusd.balanceOf(address(feeReceiver)));
        console.log("lender market shares: ", marketShares);
        console.log("lender market assets: ", currentAssets);
        console.log("mint limit: ", lender.mintLimit());
        console.log("minted amount: ", mintedAmount);
        console.log("profit: ", currentAssets > mintedAmount ? (currentAssets - mintedAmount) : 0 );

    }

    function test_basicLending() public {

        vm.startPrank(Mainnet.CURVE_OWNERSHIP_AGENT);
        crvusdController.set_debt_ceiling(
            address(factory),
            10_000_000e18
        );

        lender.setMintLimit(1_000_000e18);
        vm.stopPrank();

        printInfo();


        vm.startPrank(Mainnet.CURVE_OWNERSHIP_AGENT);

        lender.setMintLimit(500_000e18); //reduce limit
        printInfo();
        lender.reduceAmount(100_000e18); //under repay
        printInfo();
        lender.reduceAmount(600_000e18); //over repay
        printInfo();
        vm.stopPrank();

        console.log("\n\n------\n");
        vm.warp(vm.getBlockTimestamp() + 1 days);
        printInfo();
        lender.takeProfit();
        printInfo();


        console.log("\n\n------\n");
        vm.warp(vm.getBlockTimestamp() + 1 days);
        printInfo();
        vm.startPrank(Mainnet.CURVE_OWNERSHIP_AGENT);

        lender.setMintLimit(0); //reduce limit
        printInfo();
        lender.reduceAmount(500_000e18); //repay all
        printInfo();
        vm.stopPrank();

        console.log("\n\n------\n");
        vm.warp(vm.getBlockTimestamp() + 1 days);
        printInfo();
        lender.takeProfit();
        printInfo();
    }

}