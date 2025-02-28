// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "src/Constants.sol" as Constants;
import { console } from "lib/forge-std/src/console.sol";
import { ResupplyPair } from "src/protocol/ResupplyPair.sol";
import { Swapper } from "src/protocol/Swapper.sol";
import { RewardDistributorMultiEpoch } from "src/protocol/RewardDistributorMultiEpoch.sol";
import { Setup } from "test/Setup.sol";
import { PairTestBase } from "./PairTestBase.t.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { Vm } from "forge-std/Vm.sol";

contract PairTestSwaps is PairTestBase {
    function setUp() public override {
        super.setUp();
    }

    /*
    leverage in and out testing
    */
    function test_leverage() public {
        printAddresses();
        addSwapLiquidity();

        address[] memory _pairs = registry.getAllPairAddresses();
        ResupplyPair fraxresupply = ResupplyPair(_pairs[0]); 
        ResupplyPair curveresupply = ResupplyPair(_pairs[1]); 
        
        IERC20 crvusd = curveresupply.underlying();
        IERC20 frxusd = fraxresupply.underlying();
        
        deal(address(crvusd), address(this), 10_000e18);
        deal(address(frxusd), address(this), 10_000e18);
        
        IERC20 scrvusd = IERC20(Constants.Mainnet.CURVE_SCRVUSD);
        IERC20 sfrxusd = IERC20(Constants.Mainnet.SFRXUSD_ERC20);

        crvusd.approve(address(curveresupply), 999_999_999e18);
        frxusd.approve(address(fraxresupply), 999_999_999e18);

        // IERC20 crvcollateral = curveresupply.collateral();
        // IERC20 frxcollateral = fraxresupply.collateral();
        // crvusd.approve(address(crvcollateral), 999_999_999e18);
        // frxusd.approve(address(frxcollateral), 999_999_999e18);
        // frxcollateral.approve(address(fraxresupply), 999_999_999e18);
        // crvcollateral.approve(address(curveresupply), 999_999_999e18);

        // IERC4626(address(crvcollateral)).deposit(10_000e18, address(this));
        // IERC4626(address(frxcollateral)).deposit(10_000e18, address(this));
        

        address[] memory curvepath = new address[](4);
        curvepath[0] = address(stablecoin);
        curvepath[1] = address(scrvusd);
        curvepath[2] = address(curveresupply.underlying());
        curvepath[3] = address(curveresupply.collateral());

        address[] memory fraxpath = new address[](4);
        fraxpath[0] = address(stablecoin);
        fraxpath[1] = address(sfrxusd);
        fraxpath[2] = address(fraxresupply.underlying());
        fraxpath[3] = address(fraxresupply.collateral());


        address defaultswapper = registry.defaultSwappers(0);

        (address swappool, ,, uint32 swaptype) = Swapper(defaultswapper).swapPools(fraxpath[0],fraxpath[1]);
        console.log("swap pool, ", swappool);
        console.log("swap type, ", swaptype);
        printPairInfo(fraxresupply);
        printUserInfo(fraxresupply, address(this));

        console.log("check utilities and solvency..");
        uint256 maxltv = fraxresupply.maxLTV();
        uint256 toborrow = 100_000e18;
        uint256 slippage = 999e15;
        uint256 minout = utilities.getSwapRouteAmountOut(toborrow, defaultswapper, fraxpath);
        (bool issolvent, uint256 ltv, uint256 willborrow, uint256 finalcollateral) = utilities.isSolventAfterLeverage(address(fraxresupply), maxltv, address(this), 10_000e18, toborrow, slippage, defaultswapper, fraxpath);
        console.log("issolvent", issolvent);
        console.log("ltv", ltv);
        console.log("willborrow", willborrow);
        console.log("finalcollateral", finalcollateral);
        console.log("minout", minout);

        console.log("\ntry leverage...\n");
        
        // uint256 startingfraxCollateral = frxcollateral.balanceOf(address(this));
        // uint256 startingcrvusdCollateral = crvcollateral.balanceOf(address(this));
        fraxresupply.leveragedPosition(defaultswapper, toborrow, 10_000e18, 0, fraxpath);

        printPairInfo(fraxresupply);
        printUserInfo(fraxresupply, address(this));

        console.log("\nrepay with collateral..\n");
        address[] memory fraxRepayPath = new address[](4);
        fraxRepayPath[0] = address(fraxresupply.collateral());
        fraxRepayPath[1] = address(fraxresupply.underlying());
        fraxRepayPath[2] = address(sfrxusd);
        fraxRepayPath[3] = address(stablecoin);

        console.log("reusd before: ", stablecoin.balanceOf(address(this)));
        uint256 currentCollateral = fraxresupply.userCollateralBalance(address(this));
        minout = utilities.getSwapRouteAmountOut(currentCollateral, defaultswapper, fraxRepayPath);
        console.log("minout: ", minout);

        fraxresupply.repayWithCollateral(defaultswapper, currentCollateral, minout, fraxRepayPath);
        printPairInfo(fraxresupply);
        printUserInfo(fraxresupply, address(this));
        console.log("leftover reusd: ", stablecoin.balanceOf(address(this)));

        console.log("\n\ncurve pair\n");
        printPairInfo(curveresupply);
        printUserInfo(curveresupply, address(this));


        console.log("\ntry leverage...\n");
        curveresupply.leveragedPosition(defaultswapper, toborrow, 10_000e18, 0, curvepath);
        printPairInfo(curveresupply);
        printUserInfo(curveresupply, address(this));
    }

}