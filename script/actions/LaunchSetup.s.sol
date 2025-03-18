import { VestManager } from "src/dao/tge/VestManager.sol";
import { TenderlyHelper } from "script/utils/TenderlyHelper.sol";
import { DeploymentConfig } from "script/deploy/dependencies/DeploymentConfig.sol";

contract LaunchSetup is TenderlyHelper {
    address public constant PERMA_STAKER_CONVEX = 0xCCCCCccc94bFeCDd365b4Ee6B86108fC91848901;
    address public constant PERMA_STAKER_YEARN = 0x12341234B35c8a48908c716266db79CAeA0100E8;
    address public constant TREASURY = 0x44444444DBdC03c7D8291c4f4a093cb200A918FA;
    VestManager public vestManager = VestManager(0x6666666677B06CB55EbF802BB12f8876360f919c);
    address public core = 0xc07e000044F95655c11fda4cD37F70A94d7e0a7d;
    
}