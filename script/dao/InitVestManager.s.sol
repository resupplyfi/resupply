import { TenderlyHelper } from "../utils/TenderlyHelper.s.sol";
import { VestManager } from "../../src/dao/tge/VestManager.sol";

contract InitVestManager is TenderlyHelper {
    address public constant FRAX_VEST_TARGET = 0xB1748C79709f4Ba2Dd82834B8c82D4a505003f27;  
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
                0x036D8c3f9eEf5a617Ee98023420ca40014aAfCE5, // Convex
                0xDDD35ea7325779c16310af6D153869C439d09432,  // Yearn
                FRAX_VEST_TARGET,
                0x8FAd9b435388CC7784f91A1c4AC3D595f4F392a9 // Treasury
            ],
            [   // _durations
                uint256(365 days * 5),  // Convex
                uint256(365 days * 5),  // Yearn
                uint256(365 days * 1),  // Frax
                uint256(365 days * 5),  // TREASURY
                uint256(365 days * 3),  // REDEMPTIONS
                uint256(365 days * 1),  // AIRDROP_TEAM
                uint256(365 days * 2),  // AIRDROP_VICTIMS
                uint256(365 days * 5)   // AIRDROP_LOCK_PENALTY
            ],
            [ // _allocPercentages
                uint256(3333),  // Convex
                uint256(1667),  // Yearn
                uint256(83),    // Frax
                uint256(1917),  // TREASURY
                uint256(2500),  // REDEMPTIONS
                uint256(167),   // AIRDROP_TEAM
                uint256(333),   // AIRDROP_VICTIMS
                uint256(0)     // AIRDROP_LOCK_PENALTY
            ]
        );

        // Set the lock penalty merkle root
        // vestManager.setLockPenaltyMerkleRoot(bytes32(0x3adb010769f8a36c20d9ec03b89fe4d7f725c8ba133ce65faba53e18d13bf41f));
        
        vm.stopBroadcast();
    }
}