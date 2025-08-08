pragma solidity 0.8.30;

import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { Protocol } from "src/Constants.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { SafeHelper } from "script/utils/SafeHelper.sol";
import { CreateXHelper } from "script/utils/CreateXHelper.sol";
import { CreateX } from "src/Constants.sol";
import { console } from "forge-std/console.sol";

contract LaunchSetup3 is SafeHelper, CreateXHelper, BaseAction {
    address public constant deployer = Protocol.DEPLOYER;
    
    function run() public isBatch(deployer) {
        deployMode = DeployMode.FORK;

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