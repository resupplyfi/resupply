import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { Protocol, VMConstants } from "script/protocol/ProtocolConstants.sol";
import { IVestManager } from "src/interfaces/IVestManager.sol";
import { TenderlyHelper } from "script/utils/TenderlyHelper.sol";
import { CreateXHelper } from "script/utils/CreateXHelper.sol";
import { console } from "forge-std/console.sol";

contract LaunchSetup3 is TenderlyHelper, CreateXHelper, BaseAction {
    address public constant deployer = Protocol.DEPLOYER;
    address public guardian;
    address public treasuryManager;
    address public grantRecipient1 = 0xf39Ed30Cc51b65392911fEA9F33Ec1ccceEe1ed5;
    address public grantRecipient2 = 0xEF1Ed12cecC1e76fdB63C6609f9E7548c26fA041;
    
    function run() public isBatch(deployer) {
        deployMode = DeployMode.FORK;
        uint256 allocation = 1188379552775913657814831;

        _executeCore(
            Protocol.VEST_MANAGER,
            abi.encodeWithSelector(
                IVestManager.setLockPenaltyMerkleRoot.selector, 
                VMConstants.PENALTY_MERKLE_ROOT,
                allocation
            )
        );

        console.logBytes32(VMConstants.PENALTY_MERKLE_ROOT);

        require(
            IVestManager(Protocol.VEST_MANAGER).merkleRootByType(IVestManager.AllocationType.AIRDROP_LOCK_PENALTY) == 
            VMConstants.PENALTY_MERKLE_ROOT, "Lock penalty merkle root not set"
        );
        if (deployMode == DeployMode.PRODUCTION) executeBatch(true);
    }
}