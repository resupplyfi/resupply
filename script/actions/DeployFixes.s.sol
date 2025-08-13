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

contract DeployFixes is SafeHelper, CreateXHelper, BaseAction {
    address public constant deployer = Protocol.DEPLOYER;
    IResupplyRegistry public constant registry = IResupplyRegistry(Protocol.REGISTRY);
    
    function run() public isBatch(deployer) {
        deployMode = DeployMode.PRODUCTION;

        deployBorrowLimitController();
        deployBasicVaultOracle();
        deployPairDeployer();
        deployPairAdder();

        updateRegistry("BORROW_LIMIT_CONTROLLER", Protocol.BORROW_LIMIT_CONTROLLER);
        updateRegistry("PAIR_DEPLOYER", Protocol.PAIR_DEPLOYER_V2);
        updateRegistry("PAIR_ADDER", Protocol.PAIR_ADDER);
        updateRegistry("SWAPPER_ODOS", Protocol.SWAPPER_ODOS);
        updateRegistry("GUARDIAN", Protocol.OPERATOR_GUARDIAN_PROXY);
        
        if (deployMode == DeployMode.PRODUCTION) executeBatch(true);
    }

    function deployBorrowLimitController() public {
        bytes32 salt = CreateX.SALT_BORROW_LIMIT_CONTROLLER;
        bytes memory constructorArgs = abi.encode(Protocol.CORE);
        bytes memory bytecode = abi.encodePacked(vm.getCode("BorrowLimitController.sol:BorrowLimitController"), constructorArgs);
        addToBatch(
            address(createXFactory),
            encodeCREATE3Deployment(salt, bytecode)
        );
        address borrowLimitController = computeCreate3AddressFromSaltPreimage(salt, deployer, true, false);
        require(borrowLimitController == Protocol.BORROW_LIMIT_CONTROLLER, "wrong address");
        console.log("borrow limit controller deployed at", borrowLimitController);
    }

    function deployPairDeployer() public {
        // 1 Deploy new pair deployer
        // 2 Set new pair deployer on registry
        bytes32 salt = CreateX.SALT_PAIR_DEPLOYER_V2;
        (address[] memory previouslyDeployedPairs, ResupplyPairDeployer.DeployInfo[] memory previouslyDeployedPairsInfo) = DeployInfo.getDeployInfo();
        require(previouslyDeployedPairs.length > 0, "no previously deployed pairs");
        require(previouslyDeployedPairsInfo.length > 0, "no previously deployed pairs info");
        bytes memory constructorArgs = abi.encode(
            Protocol.CORE,
            Protocol.REGISTRY,
            Protocol.GOV_TOKEN,
            deployer,
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
        bytes memory bytecode = abi.encodePacked(vm.getCode("ResupplyPairDeployer.sol:ResupplyPairDeployer"), constructorArgs);
        addToBatch(
            address(createXFactory),
            encodeCREATE3Deployment(salt, bytecode)
        );
        address pairDeployer = computeCreate3AddressFromSaltPreimage(salt, deployer, true, false);
        require(pairDeployer == Protocol.PAIR_DEPLOYER_V2, "wrong address");
        console.log("pair deployer deployed at", pairDeployer);
        console.log("deployer approved", IResupplyPairDeployer(pairDeployer).approvedDeployers(address(deployer)));
        console.log("Num previously deployed pairs loaded:", previouslyDeployedPairs.length);
        require(pairDeployer.code.length > 0, "deployment failed");
        require(IResupplyPairDeployer(pairDeployer).approvedDeployers(address(deployer)), "deployer not approved");
    }

    function deployBasicVaultOracle() public {
        bytes32 salt = buildGuardedSalt(
            deployer, // deployer
            true, // enablePermissionedDeploy
            false, // enableCrossChainProtection
            uint88(uint256(keccak256(bytes("BasicVaultOracleV2")))) // randomness
        );
        bytes memory constructorArgs = abi.encode("BasicVaultOracle");
        bytes memory bytecode = abi.encodePacked(vm.getCode("BasicVaultOracle.sol:BasicVaultOracle"), constructorArgs);
        address basicVaultOracle = computeCreate3AddressFromSaltPreimage(salt, deployer, true, false);
        require(Protocol.BASIC_VAULT_ORACLE.code.length == 0, "basic vault oracle already deployed");
        addToBatch(
            address(createXFactory), 
            encodeCREATE3Deployment(salt, bytecode)
        );
        console.log("basic vault oracle v2 deployed at", basicVaultOracle);
        require(basicVaultOracle.code.length > 0, "basic vault oracle deployment failed");
        require(basicVaultOracle == Protocol.BASIC_VAULT_ORACLE, "wrong address");
    }

    function deployPairAdder() public {
        bytes32 salt = CreateX.SALT_PAIR_ADDER;
        bytes memory constructorArgs = abi.encode(Protocol.CORE, Protocol.REGISTRY);
        bytes memory bytecode = abi.encodePacked(vm.getCode("PairAdder.sol:PairAdder"), constructorArgs);
        addToBatch(address(createXFactory), encodeCREATE3Deployment(salt, bytecode));
        address pairAdder = computeCreate3AddressFromSaltPreimage(salt, deployer, true, false);
        require(pairAdder == Protocol.PAIR_ADDER, "wrong address");
        console.log("pair adder deployed at", pairAdder);
        require(pairAdder.code.length > 0, "pair adder deployment failed");
    }
    
    function updateRegistry(string memory key, address value) public {
        addToBatch(
            address(Protocol.OPERATOR_GUARDIAN_OLD),
            abi.encodeWithSelector(
                IOperatorGuardian.setRegistryAddress.selector,
                key,
                value
            )
        );
        console.log(key, "address in registry", registry.getAddress(key));
        require(value.code.length > 0, "attempted to set address to a non-deployed contract");
        require(registry.getAddress(key) == value, "registry not updated");
    }
}