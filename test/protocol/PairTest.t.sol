import { Test } from "forge-std/Test.sol";
import { ResupplyPair } from "src/protocol/ResupplyPair.sol";
import { ProtocolSetup } from "test/protocol/ProtocolSetup.sol";
import { MockToken } from "test/mocks/MockToken.sol";
import { MockConvexStaking } from "test/mocks/MockConvexStaking.sol";

contract PairTest is ProtocolSetup {
    MockToken debtToken;
    MockToken mockCollateral;
    MockConvexStaking mockStaking;
    uint poolId;

    function setUp() public override {
        super.setUp();

        debtToken = new MockToken("DebtToken", "DEBTTOKEN");
        mockCollateral = new MockToken("Collateral", "COLLATERAL");
        mockStaking = new MockConvexStaking();
        poolId = mockStaking.addPool(address(debtToken));

        pair = deployLendingPair(
            address(mockCollateral), // collateral
            address(mockStaking), // staking
            poolId // staking id
        );
    }
}
