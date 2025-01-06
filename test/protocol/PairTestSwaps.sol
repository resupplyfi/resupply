import { console } from "forge-std/console.sol";
import { ResupplyPair } from "src/protocol/ResupplyPair.sol";
import { RewardDistributorMultiEpoch } from "src/protocol/RewardDistributorMultiEpoch.sol";
import { Setup } from "test/Setup.sol";
import { PairTestBase } from "./PairTestBase.t.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

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

        
    }

}
