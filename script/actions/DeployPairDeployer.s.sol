pragma solidity 0.8.28;

import { Protocol, DeploymentConfig } from "src/Constants.sol";
import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IResupplyPairDeployer } from "src/interfaces/IResupplyPairDeployer.sol";
import { ResupplyPairDeployer } from "src/protocol/ResupplyPairDeployer.sol";
import { SafeHelper } from "script/utils/SafeHelper.sol";
import { CreateXHelper } from "script/utils/CreateXHelper.sol";
import { CreateX } from "src/Constants.sol";
import { console } from "forge-std/console.sol";
import { DeployInfo } from "test/utils/DeployInfo.sol";
import { IOperatorGuardian } from "src/interfaces/operators/IOperatorGuardian.sol";

contract DeployPairDeployer is SafeHelper, CreateXHelper, BaseAction {
    address public constant deployer = Protocol.DEPLOYER;
    IResupplyRegistry public constant registry = IResupplyRegistry(Protocol.REGISTRY);
    
    function run() public isBatch(deployer) {
        deployMode = DeployMode.FORK;

        deployPairDeployer();
       
        if (deployMode == DeployMode.PRODUCTION) executeBatch(true);
    }

    function deployPairDeployer() public {
        // 1 Deploy new pair deployer
        // 2 Set new pair deployer on registry
        bytes32 salt = CreateX.SALT_PAIR_DEPLOYER;
        (address[] memory previouslyDeployedPairs, ResupplyPairDeployer.DeployInfo[] memory previouslyDeployedPairsInfo) = DeployInfo.getDeployInfo();
        bytes memory constructorArgs = abi.encode(
            Protocol.CORE,
            Protocol.REGISTRY,
            Protocol.GOV_TOKEN,
            address(deployer),
            ResupplyPairDeployer.ConfigData({
                oracle: Protocol.BASIC_VAULT_ORACLE,
                rateCalculator: Protocol.INTEREST_RATE_CALCULATOR_V2,
                maxLTV: DeploymentConfig.DEFAULT_MAX_LTV,
                initialBorrowLimit: DeploymentConfig.DEFAULT_BORROW_LIMIT,
                liquidationFee: DeploymentConfig.DEFAULT_LIQ_FEE,
                mintFee: DeploymentConfig.DEFAULT_MINT_FEE,
                protocolRedemptionFee: DeploymentConfig.DEFAULT_PROTOCOL_REDEMPTION_FEE
            }),
            previouslyDeployedPairs,
            previouslyDeployedPairsInfo
        );
        bytes memory bytecode = abi.encodePacked(vm.getCode("PairDeployer.sol:PairDeployer"), constructorArgs);
        addToBatch(
            address(createXFactory),
            encodeCREATE3Deployment(salt, bytecode)
        );
        address pairDeployer = computeCreate3AddressFromSaltPreimage(salt, deployer, true, false);
        console.log("pair deployer deployed at", pairDeployer);
        require(pairDeployer.code.length > 0, "deployment failed");
        
        // Set address in registry
        addToBatch(
            address(Protocol.OPERATOR_GUARDIAN),
            abi.encodeWithSelector(
                IOperatorGuardian.setRegistryAddress.selector,
                "PAIR_DEPLOYER",
                pairDeployer
            )
        );
        require(registry.getAddress("PAIR_DEPLOYER") == pairDeployer, "registry not updated");
    }
}