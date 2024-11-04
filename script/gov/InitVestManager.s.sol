import { TenderlyHelper } from "../utils/TenderlyHelper.s.sol";
import { VestManager } from "../../src/dao/tge/VestManager.sol";
import { Vesting } from "../../src/dao/tge/Vesting.sol";
import "../../lib/forge-std/src/console2.sol";
import "../../lib/forge-std/src/console.sol";

contract InitVestManager is TenderlyHelper {
    VestManager public vestManager = VestManager(0x7A03f28b1A36a5fB125CE096DbB199290F14CBD9);
    Vesting public vesting = Vesting(0xBe267095Fe172FCC66A2e9d007A28F957C0a749E);
    address public core = 0x33133231E84ce1B8a040b26260Df349A61E8dF68;
    function run() public {
        setEthBalance(core, 10 ether);
        vm.startBroadcast(core);
        
        vesting.setVestManager(address(vestManager));
        
        vestManager.setInitializationParams(
            150_000_000e18,             // _maxRedeemable
            [
                bytes32(0x3adb010769f8a36c20d9ec03b89fe4d7f725c8ba133ce65faba53e18d13bf41f),
                bytes32(0x3adb010769f8a36c20d9ec03b89fe4d7f725c8ba133ce65faba53e18d13bf41f),
                bytes32(0) // We set this one later
            ],
            [   // _nonUserTargets
                0x3F75aeE5590aBB84fBb22C3F3a122Bb1092B2b93, // Treasury
                0x0Ae5acD2eDAe1CA77D2d4F0f51B3d2357dE85A98, // PermaLocker - Convex
                0x2D4aC522750bf7543E8567e18C82cfA8edB138E6  // PermaLocker - Yearn
            ],
            [   // _durations
                uint256(365 days * 5),  // TREASURY
                uint256(365 days * 5),  // PERMA_LOCKER1
                uint256(365 days * 5),  // PERMA_LOCKER2
                uint256(365 days * 5),  // REDEMPTIONS
                uint256(365 days * 1),  // AIRDROP_TEAM
                uint256(365 days * 2),  // AIRDROP_VICTIMS
                uint256(365 days * 5)   // AIRDROP_LOCK_PENALTY
            ],
            [ // _allocPercentages
                uint256(1200),  // TREASURY
                uint256(2000),  // PERMA_LOCKER1 - Convex
                uint256(1000),  // PERMA_LOCKER2 - Yearn
                uint256(1500),  // REDEMPTIONS
                uint256(100),   // AIRDROP_TEAM
                uint256(200),   // AIRDROP_VICTIMS
                uint256(0),     // AIRDROP_LOCK_PENALTY
                uint256(4000)   // Emissions, first 5 years
            ]
        );

        // Set the lock penalty merkle root
        vestManager.setLockPenaltyMerkleRoot(bytes32(0x3adb010769f8a36c20d9ec03b89fe4d7f725c8ba133ce65faba53e18d13bf41f));
        
        vm.stopBroadcast();
    }
}
