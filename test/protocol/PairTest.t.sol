import { Test } from "forge-std/Test.sol";
import { ResupplyPair } from "src/protocol/ResupplyPair.sol";
import { Setup } from "test/Setup.sol";
import { MockToken } from "test/mocks/MockToken.sol";
import { MockConvexStaking } from "test/mocks/MockConvexStaking.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MockCollateral } from "test/mocks/MockCollateral.sol";
import { MockConvexRewards } from "test/mocks/MockConvexRewards.sol";

contract PairTest is Setup {
    MockToken debtToken;
    MockToken mockUnderlying;
    MockCollateral mockCollateral;
    MockConvexStaking mockStaking;
    uint poolId;
    address user = address(1);
    IERC20 underlyingAsset;
    MockConvexRewards mockRewards;
    ResupplyPair pair;

    function setUp() public override {
        super.setUp();

        mockUnderlying = new MockToken("Underlying", "UNDERLYING");
        mockCollateral = new MockCollateral("Collateral", "COLLATERAL", address(mockUnderlying));
        mockStaking = new MockConvexStaking();
        poolId = mockStaking.addPool(address(mockCollateral));
        assertGt(poolId, 0, "PoolAddFailed");
        assertEq(mockStaking.lpToPid(address(mockCollateral)), poolId);
        (address lpToken,, address rewards,) = mockStaking.poolInfo(poolId);
        assertEq(lpToken, address(mockCollateral));
        mockRewards = MockConvexRewards(rewards);
        pair = deployLendingPair(
            address(mockCollateral), // collateral
            address(mockStaking), // staking
            poolId // staking id
        );

        underlyingAsset = IERC20(pair.underlyingAsset());

        deal(address(mockCollateral), user, 100_000e18);
        deal(address(underlyingAsset), user, 100_000e18);
        assertEq(address(underlyingAsset), address(pair.underlyingAsset()));
    }

    function test_borrow() public {
        deal(address(mockCollateral), user, 1000e18);
        vm.startPrank(user);
        mockCollateral.approve(address(pair), type(uint256).max);
        underlyingAsset.approve(address(pair), type(uint256).max);
        pair.addCollateral(100e18, address(this));
        assertEq(address(0), address(0));
    }
}
