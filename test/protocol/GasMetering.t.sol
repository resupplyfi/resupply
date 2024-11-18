import { Setup } from "test/Setup.sol";
import { ResupplyPair } from "src/protocol/ResupplyPair.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract GasMetering is Setup {

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

        collateral.approve(address(pair), type(uint256).max);
        underlying.approve(address(pair), type(uint256).max);

        deal(address(collateral), _THIS, 200_000e18);
        deal(address(underlying), _THIS, 200_000e18);
        collateral.approve(address(pair), type(uint256).max);
        underlying.approve(address(pair), type(uint256).max);

        // Seed some collateral
        pair.addCollateralVault(100_000e18, _THIS);
    }

    function test_AddCollateralVault() public {
        pair.addCollateralVault(100_000e18, user1);
    }

    function test_AddCollateral() public {
        pair.addCollateral(100_000e18, user1);
    }

    function test_RemoveCollateralVault() public {
        pair.removeCollateralVault(10_000e18, user1);
    }

    function test_RemoveCollateral() public {
        pair.removeCollateral(10_000e18, user1);
    }
}
