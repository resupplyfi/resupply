import "src/Constants.sol" as Constants;

import { console } from "forge-std/console.sol";
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
        IERC20 sfrax = IERC20(Constants.Mainnet.SFRAX_ERC20);

        
        IERC20 crvcollateral = curveresupply.collateral();
        IERC20 frxcollateral = fraxresupply.collateral();
        crvusd.approve(address(crvcollateral), 999_999_999e18);
        frxusd.approve(address(frxcollateral), 999_999_999e18);
        frxcollateral.approve(address(fraxresupply), 999_999_999e18);
        crvcollateral.approve(address(curveresupply), 999_999_999e18);

        IERC4626(address(crvcollateral)).deposit(10_000e18, address(this));
        IERC4626(address(frxcollateral)).deposit(10_000e18, address(this));
        

        address[] memory curvepath = new address[](4);
        curvepath[0] = address(stablecoin);
        curvepath[1] = address(scrvusd);
        curvepath[2] = address(curveresupply.underlying());
        curvepath[3] = address(curveresupply.collateral());

        address[] memory fraxpath = new address[](4);
        fraxpath[0] = address(stablecoin);
        fraxpath[1] = address(sfrax);
        fraxpath[2] = address(fraxresupply.underlying());
        fraxpath[3] = address(fraxresupply.collateral());


        address defaultswapper = registry.defaultSwappers(0);

        (address swappool, ,, uint32 swaptype) = Swapper(defaultswapper).swapPools(fraxpath[0],fraxpath[1]);
        console.log("swap pool, ", swappool);
        console.log("swap type, ", swaptype);

        uint256 toborrow = 100_000e18;
        uint256 startingfraxCollateral = frxcollateral.balanceOf(address(this));
        uint256 startingcrvusdCollateral = crvcollateral.balanceOf(address(this));
        fraxresupply.leveragedPosition(defaultswapper, toborrow, startingfraxCollateral, 0, fraxpath);

        // console.log("total colllateral", fraxresupply.userCollateralBalance(address(this)));
    }

}