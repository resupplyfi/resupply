pragma solidity 0.8.28;

import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { Protocol } from "src/Constants.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { SafeHelper } from "script/utils/SafeHelper.sol";
import { CreateXHelper } from "script/utils/CreateXHelper.sol";
import { CreateX } from "src/Constants.sol";
import { console } from "forge-std/console.sol";

contract DeployRedemptionHandler is SafeHelper, CreateXHelper, BaseAction {
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
        address predictedAddress = computeCreate3AddressFromSaltPreimage(salt, deployer, true, false);
        console.log("redemption handler deployed at", predictedAddress);
        require(predictedAddress.code.length > 0, "deployment failed");
    }
}