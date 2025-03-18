import { VestManager } from "src/dao/tge/VestManager.sol";
import { BaseAction } from "script/actions/BaseAction.s.sol";
import { Protocol, VMConstants } from "script/protocol/ProtocolConstants.sol";

contract InitVestManager is BaseAction {
    address public constant PERMA_STAKER_CONVEX = Protocol.PERMA_STAKER_CONVEX;
    address public constant PERMA_STAKER_YEARN = Protocol.PERMA_STAKER_YEARN;
    address public constant TREASURY = Protocol.TREASURY;
    VestManager public vestManager = VestManager(Protocol.VEST_MANAGER);
    address public deployer = Protocol.DEPLOYER;
    
    function run() public isBatch(deployer) {
        deployMode = DeployMode.FORK;
        _executeCore(
            address(vestManager),
            abi.encodeWithSelector(
                VestManager.setInitializationParams.selector,
                VMConstants.MAX_REDEEMABLE, // _maxRedeemable
                [
                    VMConstants.TEAM_MERKLE_ROOT, // Team
                    VMConstants.VICTIMS_MERKLE_ROOT, // Victims
                    bytes32(0) // Lock Penalty: We set this one later
                ],
                [   // _nonUserTargets
                    Protocol.PERMA_STAKER_CONVEX,
                    Protocol.PERMA_STAKER_YEARN,
                    VMConstants.FRAX_VEST_TARGET,
                    Protocol.TREASURY
                ],
                [   // _durations
                    VMConstants.DURATION_PERMA_STAKER,         // PERMA_STAKER: Convex
                    VMConstants.DURATION_PERMA_STAKER,         // PERMA_STAKER: Yearn
                    VMConstants.DURATION_LICENSING,            // LICENSING: FRAX
                    VMConstants.DURATION_TREASURY,             // TREASURY
                    VMConstants.DURATION_REDEMPTIONS,          // REDEMPTIONS
                    VMConstants.DURATION_AIRDROP_TEAM,         // AIRDROP_TEAM
                    VMConstants.DURATION_AIRDROP_VICTIMS,      // AIRDROP_VICTIMS
                    VMConstants.DURATION_AIRDROP_LOCK_PENALTY  // AIRDROP_LOCK_PENALTY
                ],
                [ // _allocPercentages
                    VMConstants.ALLOC_PERMA_STAKER_1,       // 33.33% PERMA_STAKER: Convex
                    VMConstants.ALLOC_PERMA_STAKER_2,       // 16.67% PERMA_STAKER: Yearn
                    VMConstants.ALLOC_LICENSING,            // 0.833% LICENSING: FRAX
                    VMConstants.ALLOC_TREASURY,             // 17.50% TREASURY
                    VMConstants.ALLOC_REDEMPTIONS,          // 25.00% REDEMPTIONS
                    VMConstants.ALLOC_AIRDROP_TEAM,         // 3.33% AIRDROP_TEAM
                    VMConstants.ALLOC_AIRDROP_VICTIMS,      // 3.33% AIRDROP_VICTIMS
                    VMConstants.ALLOC_AIRDROP_LOCK_PENALTY  // 0%   AIRDROP_LOCK_PENALTY
                ]
            )
        );
    }
}