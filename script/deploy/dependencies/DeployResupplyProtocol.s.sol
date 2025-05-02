import { CreateX } from "script/deploy/dependencies/DeploymentConfig.sol";
import { DeploymentConfig } from "script/deploy/dependencies/DeploymentConfig.sol";
import { BaseDeploy } from "./BaseDeploy.s.sol";
import { ResupplyPairDeployer } from "src/protocol/ResupplyPairDeployer.sol";
import { ResupplyPair } from "src/protocol/ResupplyPair.sol";
import { InterestRateCalculator } from "src/protocol/InterestRateCalculator.sol";
import { BasicVaultOracle } from "src/protocol/BasicVaultOracle.sol";
import { RedemptionHandler } from "src/protocol/RedemptionHandler.sol";
import { SimpleReceiver } from "src/dao/emissions/receivers/SimpleReceiver.sol";
import { SimpleReceiverFactory } from "src/dao/emissions/receivers/SimpleReceiverFactory.sol";
import { InsurancePool } from "src/protocol/InsurancePool.sol";
import { LiquidationHandler } from "src/protocol/LiquidationHandler.sol";
import { RewardHandler } from "src/protocol/RewardHandler.sol";
import { FeeDeposit } from "src/protocol/FeeDeposit.sol";
import { FeeDepositController } from "src/protocol/FeeDepositController.sol";
import { SimpleRewardStreamer } from "src/protocol/SimpleRewardStreamer.sol";
import { console } from "forge-std/console.sol";
import { ResupplyRegistry } from "src/protocol/ResupplyRegistry.sol";
import { Utilities } from "src/protocol/Utilities.sol";
import { UnderlyingOracle } from "src/protocol/UnderlyingOracle.sol";

contract DeployResupplyProtocol is BaseDeploy {

    function deployProtocolContracts() public {
        // ============================================
        // ======= Deploy ResupplyPairDeployer ========
        // ============================================
        bytes memory constructorArgs = abi.encode(
            address(core),
            address(registry),
            address(govToken),
            deployer
        );
        bytes memory bytecode = abi.encodePacked(vm.getCode("ResupplyPairDeployer.sol:ResupplyPairDeployer"), constructorArgs);
        bytes32 salt = CreateX.SALT_PAIR_DEPLOYER;
        address predictedAddress = computeCreate3AddressFromSaltPreimage(salt, deployer, true, false);
        if (!addressHasCode(predictedAddress)) {
            addToBatch(
                address(createXFactory),
                encodeCREATE3Deployment(salt, bytecode)
            );
        }
        pairDeployer = ResupplyPairDeployer(predictedAddress);
        console.log("pairDeployer deployed at", address(pairDeployer));
        writeAddressToJson("PAIR_DEPLOYER", predictedAddress);
        
        // ============================================
        // ====== Deploy InterestRateCalculator =======
        // ============================================
        constructorArgs = abi.encode(
            "Base",
            2e16 / uint256(365 days),//2%
            2
        );
        bytecode = abi.encodePacked(vm.getCode("InterestRateCalculator.sol:InterestRateCalculator"), constructorArgs);
        salt = CreateX.SALT_INTEREST_RATE_CALCULATOR;
        predictedAddress = computeCreate3AddressFromSaltPreimage(salt, deployer, true, false);
        if (!addressHasCode(predictedAddress)) {
            addToBatch(
                address(createXFactory),
                encodeCREATE3Deployment(salt, bytecode)
            );
        }
        rateCalculator = InterestRateCalculator(predictedAddress);
        console.log("InterestRateCalculator deployed at", address(rateCalculator));
        writeAddressToJson("INTEREST_RATE_CALCULATOR", predictedAddress);

        // ============================================
        // ====== Deploy BasicVaultOracle =============
        // ============================================
        constructorArgs = abi.encode(
            "Basic Vault Oracle"
        );
        bytecode = abi.encodePacked(vm.getCode("BasicVaultOracle.sol:BasicVaultOracle"), constructorArgs);
        salt = buildGuardedSalt(
            deployer, 
            true,   // enablePermissionedDeploy
            false,  // enableCrossChainProtection
            uint88(uint256(keccak256(bytes("BasicVaultOracle"))))
        );
        predictedAddress = computeCreate3AddressFromSaltPreimage(salt, deployer, true, false);
        if (!addressHasCode(predictedAddress)) {
            addToBatch(
                address(createXFactory),
                encodeCREATE3Deployment(salt, bytecode)
            );
        }
        oracle = BasicVaultOracle(predictedAddress);
        console.log("BasicVaultOracle deployed at", address(oracle));
        writeAddressToJson("BASIC_VAULT_ORACLE", predictedAddress);

        // ============================================
        // ====== Deploy UnderlyingOracle ============
        // ============================================
        constructorArgs = abi.encode(
            "Underlying Token Oracle"
        );
        bytecode = abi.encodePacked(vm.getCode("UnderlyingOracle.sol:UnderlyingOracle"), constructorArgs);
        salt = buildGuardedSalt(
            deployer, 
            true,   // enablePermissionedDeploy
            false,  // enableCrossChainProtection
            uint88(uint256(keccak256(bytes("UnderlyingOracle"))))
        );
        predictedAddress = computeCreate3AddressFromSaltPreimage(salt, deployer, true, false);
        if (!addressHasCode(predictedAddress)) {
            addToBatch(
                address(createXFactory),
                encodeCREATE3Deployment(salt, bytecode)
            );
        }
        underlyingOracle = UnderlyingOracle(predictedAddress);
        console.log("UnderlyingOracle deployed at", address(underlyingOracle));
        writeAddressToJson("UNDERLYING_ORACLE", predictedAddress);

        // ============================================
        // ====== Deploy RedemptionHandler ============
        // ============================================
        salt = CreateX.SALT_REDEMPTION_HANDLER;
        constructorArgs = abi.encode(
            address(core),
            address(registry),
            address(underlyingOracle)
        );
        bytecode = abi.encodePacked(vm.getCode("RedemptionHandler.sol:RedemptionHandler"), constructorArgs);
        predictedAddress = computeCreate3AddressFromSaltPreimage(salt, deployer, true, false);
        if (!addressHasCode(predictedAddress)) {
            addToBatch(
                address(createXFactory),
                encodeCREATE3Deployment(salt, bytecode)
            );
        }
        redemptionHandler = RedemptionHandler(predictedAddress);
        console.log("RedemptionHandler deployed at", address(redemptionHandler));
        writeAddressToJson("REDEMPTION_HANDLER", predictedAddress);
    }

    function deployRewardsContracts() public {
        address[] memory rewards = new address[](3);
        rewards[0] = address(govToken);
        rewards[1] = address(fraxToken);
        rewards[2] = address(crvusdToken);
        bytes memory result;
        bytes32 salt;

        // ============================================
        // ====== Deploy SimpleReceiver =================
        // ============================================
        bytes memory constructorArgs = abi.encode(
            address(core),
            address(emissionsController)
        );
        bytes memory bytecode = abi.encodePacked(vm.getCode("SimpleReceiver.sol:SimpleReceiver"), constructorArgs);
        salt = buildGuardedSalt(
            deployer, 
            true,   // enablePermissionedDeploy
            false,  // enableCrossChainProtection
            uint88(uint256(keccak256(bytes("SimpleReceiver"))))
        );
        address predictedAddress = computeCreate3AddressFromSaltPreimage(salt, deployer, true, false);
        if (!addressHasCode(predictedAddress)) {
            addToBatch(
                address(createXFactory),
                encodeCREATE3Deployment(salt, bytecode)
            );
        }
        console.log("SimpleReceiver implementation deployed at", address(predictedAddress));
        writeAddressToJson("SIMPLE_RECEIVER_IMPLEMENTATION", predictedAddress);

        // ============================================
        // ====== Deploy SimpleReceiverFactory ========
        // ============================================
        constructorArgs = abi.encode(
            address(core),
            address(emissionsController),
            address(predictedAddress)
        );
        bytecode = abi.encodePacked(vm.getCode("SimpleReceiverFactory.sol:SimpleReceiverFactory"), constructorArgs);
        salt = buildGuardedSalt(
            deployer, 
            true,   // enablePermissionedDeploy
            false,  // enableCrossChainProtection
            uint88(uint256(keccak256(bytes("SimpleReceiverFactory"))))
        );
        predictedAddress = computeCreate3AddressFromSaltPreimage(salt, deployer, true, false);
        if (!addressHasCode(predictedAddress)) {
            addToBatch(
                address(createXFactory),
                encodeCREATE3Deployment(salt, bytecode)
            );
        }
        receiverFactory = SimpleReceiverFactory(predictedAddress);
        console.log("SimpleReceiverFactory deployed at", address(receiverFactory));
        writeAddressToJson("SIMPLE_RECEIVER_FACTORY", address(receiverFactory));

        // ============================================
        // ====== Deploy DebtReceiver =================
        // ============================================
        result = _executeCore(
            address(receiverFactory), 
            abi.encodeWithSelector(SimpleReceiverFactory.deployNewReceiver.selector, "Debt Receiver", new address[](0))
        );
        result = abi.decode(result, (bytes)); // our result was double encoded, so we decode it once
        debtReceiver = SimpleReceiver(abi.decode(result, (address))); // decode the bytes result to an address
        console.log("Debt Receiver deployed at", address(debtReceiver));
        writeAddressToJson("DEBT_RECEIVER", address(debtReceiver));

        // ============================================
        // ====== Deploy InsurancePoolReceiver ========
        // ============================================
        result = _executeCore(
            address(receiverFactory), 
            abi.encodeWithSelector(SimpleReceiverFactory.deployNewReceiver.selector, "Insurance Receiver", new address[](0))
        );
        result = abi.decode(result, (bytes)); // our result was double encoded, so we decode it once
        insuranceEmissionsReceiver = SimpleReceiver(abi.decode(result, (address))); // decode the bytes result to an address
        console.log("Insurance Pool Receiver deployed at", address(insuranceEmissionsReceiver));
        writeAddressToJson("INSURANCE_POOL_RECEIVER", address(insuranceEmissionsReceiver));

        // ============================================
        // ====== Deploy InsurancePool ================
        // ============================================
        salt = CreateX.SALT_INSURANCE_POOL;
        constructorArgs = abi.encode(
            address(core),
            address(registry),
            address(stablecoin),
            rewards,
            address(insuranceEmissionsReceiver)
        );
        bytecode = abi.encodePacked(vm.getCode("InsurancePool.sol:InsurancePool"), constructorArgs);
        predictedAddress = computeCreate3AddressFromSaltPreimage(salt, deployer, true, false);
        if (!addressHasCode(predictedAddress)) {
            addToBatch(
                address(createXFactory),
                encodeCREATE3Deployment(salt, bytecode)
            );
        }
        insurancePool = InsurancePool(predictedAddress);
        console.log("Insurance Pool deployed at", address(insurancePool));
        writeAddressToJson("INSURANCE_POOL", predictedAddress);

        // ============================================
        // ====== Deploy LiquidationHandler ===========
        // ============================================
        salt = CreateX.SALT_LIQUIDATION_HANDLER;
        constructorArgs = abi.encode(
            address(core),
            address(registry),
            address(insurancePool)
        );
        bytecode = abi.encodePacked(vm.getCode("LiquidationHandler.sol:LiquidationHandler"), constructorArgs);
        predictedAddress = computeCreate3AddressFromSaltPreimage(salt, deployer, true, false);
        if (!addressHasCode(predictedAddress)) {
            addToBatch(
                address(createXFactory),
                encodeCREATE3Deployment(salt, bytecode)
            );
        }
        liquidationHandler = LiquidationHandler(predictedAddress);
        console.log("Liquidation Handler deployed at", address(liquidationHandler));
        writeAddressToJson("LIQUIDATION_HANDLER", predictedAddress);

        // ============================================
        // ====== Deploy IPStableStream ===============
        // ============================================
        constructorArgs = abi.encode(
            address(core),
            address(registry),
            address(stablecoin),
            address(insurancePool)
        );
        bytecode = abi.encodePacked(vm.getCode("SimpleRewardStreamer.sol:SimpleRewardStreamer"), constructorArgs);
        salt = buildGuardedSalt(
            deployer, 
            true,   // enablePermissionedDeploy
            false,  // enableCrossChainProtection
            uint88(uint256(keccak256(bytes("IPStableStream"))))
        );
        predictedAddress = computeCreate3AddressFromSaltPreimage(salt, deployer, true, false);   
        if (!addressHasCode(predictedAddress)) {
            addToBatch(
                address(createXFactory),
                encodeCREATE3Deployment(salt, bytecode)
            );
        }
        ipStableStream = SimpleRewardStreamer(predictedAddress);
        console.log("IP Stable Stream deployed at", address(ipStableStream));
        writeAddressToJson("IP_STABLE_STREAM", predictedAddress);

        // ============================================
        // ====== Deploy IP Emission Stream ===========
        // ============================================
        constructorArgs = abi.encode(
            address(core),
            address(registry),
            address(govToken),
            address(insurancePool)
        );
        bytecode = abi.encodePacked(vm.getCode("SimpleRewardStreamer.sol:SimpleRewardStreamer"), constructorArgs);
        salt = buildGuardedSalt(
            deployer, 
            true,   // enablePermissionedDeploy
            false,  // enableCrossChainProtection
            uint88(uint256(keccak256(bytes("IPEmissionStream"))))
        );  
        predictedAddress = computeCreate3AddressFromSaltPreimage(salt, deployer, true, false);
        if (!addressHasCode(predictedAddress)) {
            addToBatch(
                address(createXFactory),
                encodeCREATE3Deployment(salt, bytecode)
            );
        }
        ipEmissionStream = SimpleRewardStreamer(predictedAddress);
        console.log("IP Emission Stream deployed at", address(ipEmissionStream));
        writeAddressToJson("EMISSION_STREAM_INSURANCE_POOL", predictedAddress);

        // ============================================
        // ======= Deploy PairEmissionStream ==========
        // ============================================
        constructorArgs = abi.encode(
            address(core),
            address(registry), 
            address(govToken),
            address(0)
        );
        bytecode = abi.encodePacked(vm.getCode("SimpleRewardStreamer.sol:SimpleRewardStreamer"), constructorArgs);
        salt = buildGuardedSalt(
            deployer, 
            true,   // enablePermissionedDeploy
            false,  // enableCrossChainProtection
            uint88(uint256(keccak256(bytes("PairEmissionStream"))))
        );
        predictedAddress = computeCreate3AddressFromSaltPreimage(salt, deployer, true, false);
        if (!addressHasCode(predictedAddress)) {
            addToBatch(
                address(createXFactory),
                encodeCREATE3Deployment(salt, bytecode)
            );
        }
        pairEmissionStream = SimpleRewardStreamer(predictedAddress);
        console.log("Pair Emission Stream deployed at", address(pairEmissionStream));
        writeAddressToJson("EMISSIONS_STREAM_PAIR", predictedAddress);

        // ============================================     
        // ====== Deploy FeeDeposit ==================
        // ============================================
        constructorArgs = abi.encode(
            address(core),
            address(registry),
            address(stablecoin)
        );
        bytecode = abi.encodePacked(vm.getCode("FeeDeposit.sol:FeeDeposit"), constructorArgs);
        salt = buildGuardedSalt(
            deployer, 
            true,   // enablePermissionedDeploy
            false,  // enableCrossChain Protection
            uint88(uint256(keccak256(bytes("FeeDeposit"))))
        );
        predictedAddress = computeCreate3AddressFromSaltPreimage(salt, deployer, true, false);
        if (!addressHasCode(predictedAddress)) {
            addToBatch(
                address(createXFactory),
                encodeCREATE3Deployment(salt, bytecode)
            );
        }
        feeDeposit = FeeDeposit(predictedAddress);
        console.log("FeeDeposit deployed at", address(feeDeposit));
        writeAddressToJson("FEE_DEPOSIT", predictedAddress);

        // ============================================
        // ====== Deploy FeeDepositController ========
        // ============================================
        constructorArgs = abi.encode(
            address(core),
            address(registry),
            DeploymentConfig.FEE_SPLIT_IP,
            DeploymentConfig.FEE_SPLIT_TREASURY
        );
        bytecode = abi.encodePacked(vm.getCode("FeeDepositController.sol:FeeDepositController"), constructorArgs);
        salt = buildGuardedSalt(
            deployer, 
            true,   // enablePermissionedDeploy
            false,  // enableCrossChain Protection
            uint88(uint256(keccak256(bytes("FeeDepositController"))))
        );
        predictedAddress = computeCreate3AddressFromSaltPreimage(salt, deployer, true, false);
        if (!addressHasCode(predictedAddress)) {
            addToBatch(
                address(createXFactory),    
                encodeCREATE3Deployment(salt, bytecode)
            );
        }
        feeDepositController = FeeDepositController(predictedAddress);
        console.log("FeeDepositController deployed at", address(feeDepositController));
        writeAddressToJson("FEE_DEPOSIT_CONTROLLER", predictedAddress);

        // ============================================
        // ====== Deploy RewardHandler ================
        // ============================================
        constructorArgs = abi.encode(
            address(core),
            address(registry),
            address(insurancePool), 
            address(debtReceiver),
            address(pairEmissionStream),
            address(ipEmissionStream),
            address(ipStableStream)
        );
        bytecode = abi.encodePacked(vm.getCode("RewardHandler.sol:RewardHandler"), constructorArgs);
        salt = buildGuardedSalt(
            deployer, 
            true,   // enablePermissionedDeploy
            false,  // enableCrossChain Protection
            uint88(uint256(keccak256(bytes("RewardHandler"))))
        );
        predictedAddress = computeCreate3AddressFromSaltPreimage(salt, deployer, true, false);
        if (!addressHasCode(predictedAddress)) {
            addToBatch(
                address(createXFactory),
                encodeCREATE3Deployment(salt, bytecode)
            );
        }
        rewardHandler = RewardHandler(predictedAddress);
        console.log("RewardHandler deployed at", address(rewardHandler));
        writeAddressToJson("REWARD_HANDLER", predictedAddress);

        // ============================================
        // =============== Utilities ==================
        // ============================================
        constructorArgs = abi.encode(
            address(registry)
        );
        bytecode = abi.encodePacked(vm.getCode("Utilities.sol:Utilities"), constructorArgs);
        salt = buildGuardedSalt(
            deployer, 
            true,   // enablePermissionedDeploy
            false,  // enableCrossChain Protection
            uint88(uint256(keccak256(bytes("Utilities"))))
        );
        predictedAddress = computeCreate3AddressFromSaltPreimage(salt, deployer, true, false);
        if (!addressHasCode(predictedAddress)) {
            addToBatch(
                address(createXFactory),
                encodeCREATE3Deployment(salt, bytecode)
            );
        }
        utilities = Utilities(predictedAddress);
        console.log("Utilities deployed at", address(rewardHandler));
        writeAddressToJson("UTILITIES", predictedAddress);
    }

    function deployLendingPair(uint256 _protocolId, address _collateral, address _staking, uint256 _stakingId) public returns(address){
        require(address(pairDeployer).code.length > 0, "ResupplyPairDeployer has no code");
        bytes memory result;
        result = _executeCore(
            address(pairDeployer),
            abi.encodeWithSelector(ResupplyPairDeployer.deploy.selector,
                _protocolId,
                abi.encode(
                    _collateral,
                    address(oracle),
                    address(rateCalculator),
                    DeploymentConfig.DEFAULT_MAX_LTV,
                    defaultBorrowLimit,
                    DeploymentConfig.DEFAULT_LIQ_FEE,
                    DeploymentConfig.DEFAULT_MINT_FEE,
                    DeploymentConfig.DEFAULT_PROTOCOL_REDEMPTION_FEE
                ),
                _staking,
                _stakingId
            )
        );
        result = abi.decode(result, (bytes)); // our result was double encoded, so we decode it once
        address pair = abi.decode(result, (address));
        _executeCore(
            address(registry),
            abi.encodeWithSelector(ResupplyRegistry.addPair.selector, pair)
        );
        return pair;
    }
}
