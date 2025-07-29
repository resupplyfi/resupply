pragma solidity 0.8.28;

import "src/Constants.sol" as Constants;
import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { Protocol, Mainnet } from "src/Constants.sol";
import { TenderlyHelper } from "script/utils/TenderlyHelper.sol";
import { CreateXHelper } from "script/utils/CreateXHelper.sol";
import { CreateX } from "src/Constants.sol";
import { console } from "lib/forge-std/src/console.sol";
import { SavingsReUSD } from "src/protocol/sreusd/sreUSD.sol";
import { IOperatorGuardian } from "src/interfaces/operators/IOperatorGuardian.sol";

contract DeploySreUsd is TenderlyHelper, CreateXHelper, BaseAction {
    address public constant deployer = Protocol.DEPLOYER;
    IOperatorGuardian public guardianOperator = IOperatorGuardian(Protocol.OPERATOR_GUARDIAN);
    
    function run() public isBatch(deployer) {
        deployMode = DeployMode.FORK;

        updateRegistry("FEE_LOGGER", address(Protocol.FEE_LOGGER));
        updateRegistry("PRICE_WATCHER", address(Protocol.PRICE_WATCHER));
        updateRegistry("SREUSD", address(Protocol.SREUSD));
        deployContracts();

        if (deployMode == DeployMode.PRODUCTION) executeBatch(false);
    }


    function deployContracts() public {
        // 1. Deploy SavingsReUSD
        bytes32 salt = CreateX.SALT_SREUSD;
        bytes memory constructorArgs = abi.encode(
            address(Protocol.CORE),
            address(Protocol.REGISTRY),
            Constants.Mainnet.LAYERZERO_ENDPOINTV2,
            address(Protocol.STABLECOIN),
            "Savings reUSD",
            "sreUSD",
            0 // start with zero stream rate, and us gov prop to update on launch to --> uint256(2e17) / 365 days // 20% apr max distribution rate
        );
        bytes memory bytecode = abi.encodePacked(vm.getCode("sreUSD.sol:SavingsReUSD"), constructorArgs);
        addToBatch(
            address(CreateX.CREATEX_DEPLOYER),
            encodeCREATE3Deployment(salt, bytecode)
        );
        address predictedAddress = computeCreate3AddressFromSaltPreimage(salt, deployer, true, false);
        console.log("sreUSD deployed at", predictedAddress);
        require(predictedAddress.code.length > 0, "deployment failed");
        SavingsReUSD sreUSD = SavingsReUSD(predictedAddress);

        // 2. Deploy FeeDepositController
        salt = CreateX.SALT_FEE_DEPOSIT_CONTROLLER;
        constructorArgs = abi.encode(
            address(Protocol.CORE),
            address(Protocol.REGISTRY),
            200_000,// Max additional fee: 2%
            1_000,  // Insurance split: 10%
            500,    // Treasury split: 5%
            1_500   // Staked stable split: 15%
        ); // Stakers = remaining 70%
        bytecode = abi.encodePacked(vm.getCode("FeeDepositController.sol:FeeDepositController"), constructorArgs);
        addToBatch(
            address(CreateX.CREATEX_DEPLOYER),
            encodeCREATE3Deployment(salt, bytecode)
        );
        predictedAddress = computeCreate3AddressFromSaltPreimage(salt, deployer, true, false);
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
        addToBatch(
            address(CreateX.CREATEX_DEPLOYER),
            encodeCREATE3Deployment(salt, bytecode)
        );
        predictedAddress = computeCreate3AddressFromSaltPreimage(salt, deployer, true, false);
        console.log("RewardHandler deployed at", predictedAddress);
        require(predictedAddress.code.length > 0, "deployment failed");

        // 4. Deploy PriceWatcher
        salt = CreateX.SALT_PRICE_WATCHER;
        constructorArgs = abi.encode(
            address(Protocol.REGISTRY)
        );
        salt = CreateX.SALT_PRICE_WATCHER;
        bytecode = abi.encodePacked(vm.getCode("PriceWatcher.sol:PriceWatcher"), constructorArgs);
        addToBatch(
            address(CreateX.CREATEX_DEPLOYER),
            encodeCREATE3Deployment(salt, bytecode)
        );
        predictedAddress = computeCreate3AddressFromSaltPreimage(salt, deployer, true, false);
        console.log("PriceWatcher deployed at", predictedAddress);
        require(predictedAddress.code.length > 0, "deployment failed");

        // 5. Deploy InterestRateCalculatorV2
        salt = CreateX.SALT_INTEREST_RATE_CALCULATOR_V2;
        constructorArgs = abi.encode(
            "V2", // Suffix
            2e16 / uint256(365 days), //2% apr min rate
            5e17, // Rate ratio base
            1e17, // Rate ratio additional
            address(Protocol.PRICE_WATCHER) // price watcher
        );
        bytecode = abi.encodePacked(vm.getCode("InterestRateCalculatorV2.sol:InterestRateCalculatorV2"), constructorArgs);
        addToBatch(
            address(CreateX.CREATEX_DEPLOYER),
            encodeCREATE3Deployment(salt, bytecode)
        );
        predictedAddress = computeCreate3AddressFromSaltPreimage(salt, deployer, true, false);
        console.log("InterestRateCalculatorV2 deployed at", predictedAddress);

        // 6. Deploy FeeLogger
        salt = CreateX.SALT_FEE_LOGGER;
        constructorArgs = abi.encode(
            address(Protocol.CORE),
            address(Protocol.REGISTRY)
        );
        bytecode = abi.encodePacked(vm.getCode("FeeLogger.sol:FeeLogger"), constructorArgs);
        addToBatch(
            address(CreateX.CREATEX_DEPLOYER),
            encodeCREATE3Deployment(salt, bytecode)
        );
        predictedAddress = computeCreate3AddressFromSaltPreimage(salt, deployer, true, false);
        console.log("FeeLogger deployed at", predictedAddress);
        require(predictedAddress.code.length > 0, "deployment failed");
    }

    function updateRegistry(string memory key, address value) public {
        addToBatch(
            address(guardianOperator),
            abi.encodeWithSelector(
                IOperatorGuardian.setRegistryAddress.selector,
                key,
                value
            )
        );
    }
}