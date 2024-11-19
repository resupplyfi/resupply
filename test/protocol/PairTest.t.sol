import { console } from "forge-std/console.sol";
import { ResupplyPair } from "src/protocol/ResupplyPair.sol";
import { Setup } from "test/Setup.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract PairTest is Setup {
    ResupplyPair pair;
    IERC20 collateral;
    IERC20 underlying;

    function setUp() public override {
        super.setUp();

        deployDefaultLendingPairs();
        address[] memory _pairs = registry.getAllPairAddresses();
        pair = ResupplyPair(_pairs[0]); 
        collateral = pair.collateral();
        underlying = pair.underlying();
        printPairInfo();

        collateral.approve(address(pair), type(uint256).max);
        underlying.approve(address(pair), type(uint256).max);
    }

    function printPairInfo() public view {
        console.log("pair", address(pair));
        console.log("collateral", address(collateral));
        console.log("underlying", address(underlying));
    }

    function test_AddCollateral() public {
        assertEq(pair.userCollateralBalance(_THIS), 0);

        uint256 amount = 100e18;
        deal(address(collateral), address(this), amount);

        pair.addCollateralVault(amount, address(this));

        assertEq(pair.userCollateralBalance(_THIS), amount);
    }

    function test_AddCollateralUnderlying() public {
        assertEq(pair.userCollateralBalance(_THIS), 0);
        
        uint256 amount = 100e18;
        deal(address(underlying), address(this), amount);

        pair.addCollateral(amount, address(this));
        uint256 shares = IERC4626(address(collateral)).convertToShares(amount);

        assertEq(pair.userCollateralBalance(_THIS), shares);
    }

    function test_RemoveCollateral() public {
        addCollateral(100_000e18);
        uint256 shares = pair.userCollateralBalance(_THIS);
        uint256 startBalance = collateral.balanceOf(address(this));
        // Make sure we get out
        pair.removeCollateralVault(shares, address(this));
        assertEq(collateral.balanceOf(address(this)), startBalance + shares);
    }

    function test_RemoveCollateralUnderlying() public {
        addCollateral(100_000e18);
        uint256 shares = pair.userCollateralBalance(_THIS);
        uint256 amount = convertToAssets(address(collateral), shares);
        uint256 startBalance = underlying.balanceOf(address(this));
        pair.removeCollateral(shares, address(this));
        assertEq(underlying.balanceOf(address(this)), startBalance + amount);
    }

    function test_Borrow() public {
        uint256 collateralAmount = 110_000e18;
        uint256 borrowAmount = 100_000e18;

        addCollateral(convertToShares(address(collateral), collateralAmount));
        borrow(borrowAmount, 0);
    }

    function addCollateral(uint256 amount) public {
        deal(address(collateral), address(this), amount);
        console.log("Adding collateral xxx", amount, collateral.balanceOf(address(this)));
        pair.addCollateralVault(amount, address(this));
        // assertEq(pair.userCollateralBalance(_THIS), amount);
    }

    function removeCollateral(uint256 amount) public {
        uint256 startCollateralBalance = pair.userCollateralBalance(_THIS);
        pair.removeCollateralVault(amount, address(this));
        // assertEq(pair.userCollateralBalance(_THIS), startCollateralBalance - amount);
    }

    // collateralAmount is the amount of collateral to add for the borrow
    function borrow(uint256 amount, uint256 collateralAmount) public {
        pair.borrow(amount, collateralAmount, address(this));
    }

    function convertToShares(address token, uint256 amount) public view returns (uint256) {
        return IERC4626(token).convertToShares(amount);
    }

    function convertToAssets(address token, uint256 shares) public view returns (uint256) {
        return IERC4626(token).convertToAssets(shares);
    }
}
