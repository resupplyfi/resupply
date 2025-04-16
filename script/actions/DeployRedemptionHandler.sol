import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { Protocol, Prisma } from "script/protocol/ProtocolConstants.sol";
import { Guardian } from "src/dao/operators/Guardian.sol";
import { ITreasuryManager } from "src/interfaces/ITreasuryManager.sol";
import { ITreasury } from "src/interfaces/ITreasury.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { IGuardian } from "src/interfaces/IGuardian.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { TenderlyHelper } from "script/utils/TenderlyHelper.sol";
import { CreateXHelper } from "script/utils/CreateXHelper.sol";
import { CreateX } from "script/deploy/dependencies/DeploymentConfig.sol";
import { IPrismaCore } from "src/interfaces/IPrismaCore.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { console } from "forge-std/console.sol";
import { ISimpleReceiver } from "src/interfaces/ISimpleReceiver.sol";
import { ITreasuryManager } from "src/interfaces/ITreasuryManager.sol";
import { ICore } from "src/interfaces/ICore.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPrismaVoterProxy } from "src/interfaces/prisma/IPrismaVoterProxy.sol";

contract LaunchSetup3 is TenderlyHelper, CreateXHelper, BaseAction {
    address public constant deployer = Protocol.DEPLOYER;
    
    function run() public isBatch(deployer) {
        deployMode = DeployMode.PRODUCTION;

        deployRedemptionHandler();
       
        if (deployMode == DeployMode.PRODUCTION) executeBatch(true);
    }

    function deployRedemptionHandler() public {
        // 1 Deploy redemption handler
        // 2 Set on registry
        bytes32 salt = CreateX.SALT_REDEMPTION_HANDLER;
        bytes memory constructorArgs = abi.encode(
            Protocol.CORE,
            Protocol.REGISTRY,
            Protocol.UNDERLYING_ORACLE
        );
        bytes memory bytecode = abi.encodePacked(vm.getCode("RedemptionHandler.sol:RedemptionHandler"), constructorArgs);
        addToBatch(
            address(createXFactory),
            encodeCREATE3Deployment(salt, bytecode)
        );
        address redemptionH = computeCreate3AddressFromSaltPreimage(salt, deployer, true, false);
        console.log("redemption handler deployed at", redemptionH);
        require(redemptionH.code.length > 0, "deployment failed");
        
        // Set address in registry
        _executeCore(
            address(Protocol.REGISTRY),
            abi.encodeWithSelector(
                IResupplyRegistry.setRedemptionHandler.selector,
                redemptionH
            )
        );
    }
}