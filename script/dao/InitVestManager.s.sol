import { TenderlyHelper } from "../utils/TenderlyHelper.s.sol";
import { VestManager } from "../../src/dao/tge/VestManager.sol";

contract InitVestManager is TenderlyHelper {
    VestManager public vestManager = VestManager(0xdBF2e66A57fdaceaA3CD3e6ae90D1d39255f3668);
    address public core = 0x33133231E84ce1B8a040b26260Df349A61E8dF68;
    function run() public {
        setEthBalance(core, 10 ether);
        vm.startBroadcast(core);
        
        vestManager.setInitializationParams(
            150_000_000e18,             // _maxRedeemable
            [
                bytes32(0x3adb010769f8a36c20d9ec03b89fe4d7f725c8ba133ce65faba53e18d13bf41f),
                bytes32(0x3adb010769f8a36c20d9ec03b89fe4d7f725c8ba133ce65faba53e18d13bf41f),
                bytes32(0) // We set this one later
            ],
            [   // _nonUserTargets
                0x8FAd9b435388CC7784f91A1c4AC3D595f4F392a9, // Treasury
                0x036D8c3f9eEf5a617Ee98023420ca40014aAfCE5, // PermaLocker - Convex
                0xDDD35ea7325779c16310af6D153869C439d09432  // PermaLocker - Yearn
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
        // vestManager.setLockPenaltyMerkleRoot(bytes32(0x3adb010769f8a36c20d9ec03b89fe4d7f725c8ba133ce65faba53e18d13bf41f));
        
        vm.stopBroadcast();
    }
}