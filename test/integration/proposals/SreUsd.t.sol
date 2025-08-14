// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol, DeploymentConfig, CreateX, Mainnet } from "src/Constants.sol";
import { console } from "forge-std/console.sol";
import { SavingsReUSD } from "src/protocol/sreusd/sreUSD.sol";
import { BaseProposalTest } from "test/integration/proposals/BaseProposalTest.sol";
import { PermissionHelper } from "script/utils/PermissionHelper.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IResupplyPairDeployer } from "src/interfaces/IResupplyPairDeployer.sol";
import { ResupplyPair } from "src/protocol/ResupplyPair.sol";
import { DeployInfo } from "script/actions/DeployFixes.s.sol";
import { LaunchSreUsd } from "script/proposals/LaunchSreUsd.s.sol";
import { ICreateX } from "src/interfaces/ICreateX.sol";
import { CreateXHelper } from "script/utils/CreateXHelper.sol";

contract SreUsdTest is BaseProposalTest, CreateXHelper {
    ICreateX createX = ICreateX(CreateX.CREATEX_DEPLOYER);
    LaunchSreUsd launchScript;
    
    function setUp() public override {
        super.setUp();
        launchScript = new LaunchSreUsd();
        setRegistryValues();
        deployContracts();
        console.log("Deployed contracts");
        IVoter.Action[] memory actions = launchScript.buildProposalCalldata();
        uint256 proposalId = createProposal(actions);
        simulatePassingVote(proposalId);
        executeProposal(proposalId);
    }

    function setRegistryValues() public {
        updateRegistry("FEE_LOGGER", address(Protocol.FEE_LOGGER));
        updateRegistry("PRICE_WATCHER", address(Protocol.PRICE_WATCHER));
        updateRegistry("SREUSD", address(Protocol.SREUSD));
    }

     function deployContracts() public {
        // 1. Deploy SavingsReUSD
        bytes32 salt = CreateX.SALT_SREUSD;
        bytes memory constructorArgs = abi.encode(
            address(Protocol.CORE),
            address(Protocol.REGISTRY),
            Mainnet.LAYERZERO_ENDPOINTV2,
            address(Protocol.STABLECOIN),
            "Savings reUSD",
            "sreUSD",
            0 // start with zero stream rate, and us gov prop to update on launch to --> uint256(2e17) / 365 days // 20% apr max distribution rate
        );
        bytes memory bytecode = abi.encodePacked(vm.getCode("sreUSD.sol:SavingsReUSD"), constructorArgs);
        vm.startPrank(Protocol.DEPLOYER);
        createX.deployCreate3(salt, bytecode);

        address predictedAddress = computeCreate3AddressFromSaltPreimage(salt, Protocol.DEPLOYER, true, false);
        console.log("sreUSD deployed at", predictedAddress);
        require(predictedAddress.code.length > 0, "deployment failed");
        SavingsReUSD sreUSD = SavingsReUSD(predictedAddress);

        // 2. Deploy FeeDepositController
        salt = CreateX.SALT_FEE_DEPOSIT_CONTROLLER;
        constructorArgs = abi.encode(
            address(Protocol.CORE),
            address(Protocol.REGISTRY),
            200_000,// Max additional fee: 2%
            DeploymentConfig.FEE_SPLIT_IP,          // Insurance split: 10%
            DeploymentConfig.FEE_SPLIT_TREASURY,    // Treasury split: 5%
            DeploymentConfig.FEE_SPLIT_SREUSD       // Staked stable split: 15%
        ); // Stakers = remaining 70%
        bytecode = abi.encodePacked(vm.getCode("FeeDepositController.sol:FeeDepositController"), constructorArgs);
        createX.deployCreate3(salt, bytecode);
        predictedAddress = computeCreate3AddressFromSaltPreimage(salt, Protocol.DEPLOYER, true, false);
        console.log("FeeDepositController deployed at", predictedAddress);
        require(predictedAddress.code.length > 0, "deployment failed");

        // 3. Deploy RewardHandler
        salt = CreateX.SALT_REWARD_HANDLER;
        constructorArgs = abi.encode(
            address(Protocol.CORE),
            address(Protocol.REGISTRY),
            address(Protocol.INSURANCE_POOL),
            address(Protocol.DEBT_RECEIVER),
            address(Protocol.EMISSIONS_STREAM_PAIR),
            address(Protocol.EMISSION_STREAM_INSURANCE_POOL),
            address(Protocol.IP_STABLE_STREAM)
        );
        bytecode = abi.encodePacked(vm.getCode("RewardHandler.sol:RewardHandler"), constructorArgs);
        createX.deployCreate3(salt, bytecode);
        predictedAddress = computeCreate3AddressFromSaltPreimage(salt, Protocol.DEPLOYER, true, false);
        console.log("RewardHandler deployed at", predictedAddress);
        require(predictedAddress.code.length > 0, "deployment failed");

        // 4. Deploy PriceWatcher
        salt = CreateX.SALT_PRICE_WATCHER;
        constructorArgs = abi.encode(
            address(Protocol.REGISTRY)
        );
        salt = CreateX.SALT_PRICE_WATCHER;
        bytecode = abi.encodePacked(vm.getCode("PriceWatcher.sol:PriceWatcher"), constructorArgs);
        createX.deployCreate3(salt, bytecode);
        predictedAddress = computeCreate3AddressFromSaltPreimage(salt, Protocol.DEPLOYER, true, false);
        console.log("PriceWatcher deployed at", predictedAddress);
        require(predictedAddress.code.length > 0, "deployment failed");

        // 5. Deploy InterestRateCalculatorV2
        salt = CreateX.SALT_INTEREST_RATE_CALCULATOR_V2;
        constructorArgs = abi.encode(
            "V2", // Suffix
            2e16 / uint256(365 days) * 2, //4% - we multiply by 2 to adjust for rate ratio base
            5e17, // Rate ratio base
            1e17, // Rate ratio additional
            address(Protocol.PRICE_WATCHER) // price watcher
        );
        bytecode = abi.encodePacked(vm.getCode("InterestRateCalculatorV2.sol:InterestRateCalculatorV2"), constructorArgs);
        createX.deployCreate3(salt, bytecode);
        predictedAddress = computeCreate3AddressFromSaltPreimage(salt, Protocol.DEPLOYER, true, false);
        console.log("InterestRateCalculatorV2 deployed at", predictedAddress);

        // 6. Deploy FeeLogger
        salt = CreateX.SALT_FEE_LOGGER;
        constructorArgs = abi.encode(
            address(Protocol.CORE),
            address(Protocol.REGISTRY)
        );
        bytecode = abi.encodePacked(vm.getCode("FeeLogger.sol:FeeLogger"), constructorArgs);
        createX.deployCreate3(salt, bytecode);
        predictedAddress = computeCreate3AddressFromSaltPreimage(salt, Protocol.DEPLOYER, true, false);
        console.log("FeeLogger deployed at", predictedAddress);
        require(predictedAddress.code.length > 0, "deployment failed");
        vm.stopPrank();
    }

    function updateRegistry(string memory key, address value) public {
        vm.startPrank(address(core));
        registry.setAddress(key, value);
        vm.stopPrank();
    }
}