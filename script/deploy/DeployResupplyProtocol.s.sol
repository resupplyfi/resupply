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
import { ICore } from "src/interfaces/ICore.sol";
import { ResupplyRegistry } from "src/protocol/ResupplyRegistry.sol";

contract DeployResupplyProtocol is BaseDeploy {

    function deployProtocolContracts(address _sender) public doBroadcast(_sender) {
        pairDeployer = new ResupplyPairDeployer(
            address(core),
            address(registry),
            address(govToken),
            dev
        );
        console.log("pairDeployer deployed at", address(pairDeployer));
        rateCalculator = new InterestRateCalculator(
            "Base",
            2e16 / uint256(365 days),//2%
            2
        );
        console.log("InterestRateCalculator deployed at", address(rateCalculator));
        oracle = new BasicVaultOracle("Basic Vault Oracle");

        redemptionHandler = new RedemptionHandler(address(core),address(registry));
        console.log("RedemptionHandler deployed at", address(redemptionHandler));
    }

    function deployRewardsContracts(address _sender) doBroadcast(_sender) public {
        address[] memory rewards = new address[](3);
        rewards[0] = address(govToken);
        rewards[1] = address(fraxToken);
        rewards[2] = address(crvusdToken);

        address simpleReceiverImplementation = address(new 
            SimpleReceiver(
                address(core), 
                address(emissionsController)
            )
        );
        console.log("SimpleReceiver deployed at", address(simpleReceiverImplementation));
        receiverFactory = new SimpleReceiverFactory(address(core), 
            address(emissionsController), 
            address(simpleReceiverImplementation)
        );
        console.log("SimpleReceiverFactory deployed at", address(receiverFactory));
        ICore _core = ICore(core);
        bytes memory result = _core.execute(
            address(receiverFactory), 
            abi.encodeWithSelector(SimpleReceiverFactory.deployNewReceiver.selector, "Debt Receiver", new address[](0))
        );
        console.log("Result:", uint256(bytes32(result)));
        debtReceiver = SimpleReceiver(address(uint160(uint256(bytes32(result))))); // cast the bytes result to an address
        console.log("Debt Receiver deployed at", address(debtReceiver));
        result = _core.execute(
            address(receiverFactory), 
            abi.encodeWithSelector(SimpleReceiverFactory.deployNewReceiver.selector, "Insurance Receiver", new address[](0))
        );
        console.log("Result:", uint256(bytes32(result)));
        insuranceEmissionsReceiver = SimpleReceiver(address(uint160(uint256(bytes32(result))))); // cast the bytes result to an address
        console.log("Insurance Receiver deployed at", address(insuranceEmissionsReceiver));
        insurancePool = new InsurancePool(
                address(core), //core
                address(stablecoin),
                rewards,
                address(registry),
                address(insuranceEmissionsReceiver)
        );
        console.log("Insurance Pool deployed at", address(insurancePool));
        liquidationHandler = new LiquidationHandler(address(core), address(registry), address(insurancePool));
        console.log("Liquidation Handler deployed at", address(liquidationHandler));
        ipStableStream = new SimpleRewardStreamer(address(stablecoin), 
            address(registry), 
            address(core), 
            address(insurancePool)
        );
        console.log("IP Stable Stream deployed at", address(ipStableStream));
        ipEmissionStream = new SimpleRewardStreamer(address(govToken),
            address(registry),
            address(core),
            address(insurancePool)
        );
        console.log("IP Emission Stream deployed at", address(ipEmissionStream));

        //todo queue rewards to pools

        pairEmissionStream = new SimpleRewardStreamer(address(govToken), 
            address(registry), 
            address(core), 
            address(0)
        );
        console.log("Pair Emission Stream deployed at", address(pairEmissionStream));
        feeDeposit = new FeeDeposit(address(core), address(registry), address(stablecoin));
        feeDepositController = new FeeDepositController(address(core), 
            address(registry), 
            address(feeDeposit), 
            1500, 
            500
        );
        console.log("FeeDepositController deployed at", address(feeDepositController));
        rewardHandler = new RewardHandler(
            address(core),
            address(registry),
            address(insurancePool), 
            address(debtReceiver),
            address(pairEmissionStream),
            address(ipEmissionStream),
            address(ipStableStream)
        );
        console.log("RewardHandler deployed at", address(rewardHandler));
    }

    function deployLendingPair(address _sender, address _collateral, address _staking, uint256 _stakingId) public doBroadcast(_sender) returns(address){
        require(address(pairDeployer).code.length > 0, "ResupplyPairDeployer has no code");
        address _pairAddress = pairDeployer.deploy(
            abi.encode(
                _collateral,
                address(oracle),
                address(rateCalculator),
                DEFAULT_MAX_LTV, //max ltv 75%
                DEFAULT_BORROW_LIMIT,
                DEFAULT_LIQ_FEE,
                DEFAULT_MINT_FEE,
                DEFAULT_PROTOCOL_REDEMPTION_FEE
            ),
            _staking,
            _stakingId
        );
        console.log("ResupplyPair deployed at", _pairAddress);
        ICore(core).execute(address(registry), abi.encodeWithSelector(ResupplyRegistry.addPair.selector, _pairAddress));
        return _pairAddress;
    }
}
