import { VestManager } from "src/dao/tge/VestManager.sol";
import { TenderlyHelper } from "script/utils/TenderlyHelper.sol";
import { DeploymentConfig } from "script/deploy/dependencies/DeploymentConfig.sol";

contract InitVestManager is TenderlyHelper {
    address public constant PERMA_STAKER_CONVEX = 0xCCCCCccc94bFeCDd365b4Ee6B86108fC91848901;
    address public constant PERMA_STAKER_YEARN = 0x12341234B35c8a48908c716266db79CAeA0100E8;
    address public constant TREASURY = 0x44444444DBdC03c7D8291c4f4a093cb200A918FA;
    VestManager public vestManager = VestManager(0x6666666677B06CB55EbF802BB12f8876360f919c);
    address public core = 0xc07e000044F95655c11fda4cD37F70A94d7e0a7d;
    
    function run() public {
        setEthBalance(core, 1e18);
        vm.startBroadcast(core);
        vestManager.setInitializationParams(
            150_000_000e18,             // _maxRedeemable
            [
                bytes32(0x64feeba695e9074a9ffba7755be2733319de2ed77aa6b6bee2a18a0a17ff2a7f),
                bytes32(0x64feeba695e9074a9ffba7755be2733319de2ed77aa6b6bee2a18a0a17ff2a7f),
                bytes32(0) // We set this one later
            ],
            [   // _nonUserTargets
                CONVEX_PERMA_STAKER,
                YEARN_PERMA_STAKER,
                DeploymentConfig.FRAX_VEST_TARGET,
                TREASURY
            ],
            [   // _durations
                uint256(365 days * 5),  // PERMA_STAKER: Convex
                uint256(365 days * 5),  // PERMA_STAKER: Yearn
                uint256(365 days * 1),  // LICENSING: FRAX
                uint256(365 days * 5),  // TREASURY
                uint256(365 days * 3),  // REDEMPTIONS
                uint256(365 days * 1),  // AIRDROP_TEAM
                uint256(365 days * 2),  // AIRDROP_VICTIMS
                uint256(365 days * 5)   // AIRDROP_LOCK_PENALTY
            ],
            [ // _allocPercentages
                uint256(333333333333333333),  // 33.33% PERMA_STAKER: Convex
                uint256(166666666666666666),  // 16.67% PERMA_STAKER: Yearn
                uint256(8333333333333334),    // 0.833% LICENSING: FRAX
                uint256(175000000000000000),  // 17.50% TREASURY
                uint256(250000000000000000),  // 25.00% REDEMPTIONS
                uint256(33333333333333333),   // 3.33% AIRDROP_TEAM
                uint256(33333333333333334),   // 3.33% AIRDROP_VICTIMS
                uint256(0)                    // 0%   AIRDROP_LOCK_PENALTY
            ]
        );
        vm.stopBroadcast();
    }
}