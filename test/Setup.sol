// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.22;

import "src/Constants.sol" as Constants;

// DAO Contracts
import { Test } from "lib/forge-std/src/Test.sol";
import { console } from "lib/forge-std/src/console.sol";
import { IERC20, SafeERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import { IGovStaker } from "src/interfaces/IGovStaker.sol";
import { GovStaker } from "src/dao/staking/GovStaker.sol";
import { Core } from "src/dao/Core.sol";
import { Voter } from "src/dao/Voter.sol";
import { MockToken } from "./mocks/MockToken.sol";
import { GovStakerEscrow } from "src/dao/staking/GovStakerEscrow.sol";
import { IGovStakerEscrow } from "src/interfaces/IGovStakerEscrow.sol";
import { EmissionsController } from "src/dao/emissions/EmissionsController.sol";
import { GovToken } from "src/dao/GovToken.sol";
import { IGovToken } from "src/interfaces/IGovToken.sol";
import { VestManager } from "src/dao/tge/VestManager.sol";
import { Treasury } from "src/dao/Treasury.sol";
import { PermaLocker } from "src/dao/tge/PermaLocker.sol";
import { ResupplyRegistry } from "src/protocol/ResupplyRegistry.sol";

// Protocol Contracts
import { Stablecoin } from "src/protocol/Stablecoin.sol";
import { ResupplyPair } from "src/protocol/ResupplyPair.sol";
import { ResupplyRegistry } from "src/protocol/ResupplyRegistry.sol";
import { ResupplyPairDeployer } from "src/protocol/ResupplyPairDeployer.sol";
import { InsurancePool } from "src/protocol/InsurancePool.sol";
import { BasicVaultOracle } from "src/protocol/BasicVaultOracle.sol";
import { InterestRateCalculator } from "src/protocol/InterestRateCalculator.sol";
import { RedemptionHandler } from "src/protocol/RedemptionHandler.sol";
import { LiquidationHandler } from "src/protocol/LiquidationHandler.sol";
import { RewardHandler } from "src/protocol/RewardHandler.sol";

// Incentive Contracts
import { SimpleRewardStreamer } from "src/protocol/SimpleRewardStreamer.sol";
import { FeeDeposit } from "src/protocol/FeeDeposit.sol";
import { FeeDepositController } from "src/protocol/FeeDepositController.sol";
import { SimpleReceiver } from "src/dao/emissions/receivers/SimpleReceiver.sol";
import { SimpleReceiverFactory } from "src/dao/emissions/receivers/SimpleReceiverFactory.sol";

contract Setup is Test {

    // Deployer constants
    uint256 public constant epochLength = 1 weeks;
    address public immutable _THIS;
    uint256 internal constant DEFAULT_MAX_LTV = 95_000; // 95% with 1e5 precision
    uint256 internal constant DEFAULT_LIQ_FEE = 5_000; // 5% with 1e5 precision
    uint256 internal constant DEFAULT_BORROW_LIMIT = 5_000_000 * 1e18;
    uint256 internal constant DEFAULT_MINT_FEE = 0; //1e5 prevision
    uint256 internal constant DEFAULT_PROTOCOL_REDEMPTION_FEE = 1e18 / 2; //half
    uint64 internal constant FIFTY_BPS = 158_247_046;
    uint64 internal constant ONE_PERCENT = FIFTY_BPS * 2;
    uint64 internal constant ONE_BPS = FIFTY_BPS / 50;
    uint256 internal constant GOV_TOKEN_INITIAL_SUPPLY = 60_000_000e18;
    address internal constant FRAX_VEST_TARGET = address(0xB1748C79709f4Ba2Dd82834B8c82D4a505003f27);
    address internal constant BURN_ADDRESS = address(0xdead);

    Core public core;
    GovStaker public staker;
    Voter public voter;
    GovToken public govToken;
    GovToken public stakingToken;
    EmissionsController public emissionsController;
    VestManager public vestManager;
    ResupplyRegistry public registry;
    address public user1 = address(0x11);
    address public user2 = address(0x22);
    address public user3 = address(0x33);
    address public dev = address(0x42069);
    address public tempGov = address(987);
    Treasury public treasury;
    PermaLocker public permaLocker1;
    PermaLocker public permaLocker2;
    Stablecoin public stablecoin;
    BasicVaultOracle public oracle;
    InterestRateCalculator public rateCalculator;
    ResupplyPairDeployer public deployer;
    RedemptionHandler public redemptionHandler;
    LiquidationHandler public liquidationHandler;
    RewardHandler public rewardHandler;
    FeeDeposit public feeDeposit;
    FeeDepositController public feeDepositController;
    SimpleRewardStreamer public ipStableStream;
    SimpleRewardStreamer public ipEmissionStream;
    SimpleRewardStreamer public pairEmissionStream;
    InsurancePool public insurancePool;
    SimpleReceiverFactory public receiverFactory;
    SimpleReceiver public debtReceiver;
    SimpleReceiver public insuranceEmissionsReceiver;
    IERC20 public fraxToken;
    IERC20 public crvusdToken;

    constructor() {
        _THIS = address(this);
    }

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_URL"));
        deployDaoContracts();
        deployProtocolContracts();
        deployRewardsContracts();
        setInitialEmissionReceivers();
        deal(address(govToken), user1, 1_000_000 * 10 ** 18);
        vm.prank(user1);
        govToken.approve(address(staker), type(uint256).max);

        fraxToken = IERC20(address(Constants.Mainnet.FRAX_ERC20));
        crvusdToken = IERC20(address(Constants.Mainnet.CURVE_USD_ERC20));


        // Setup registry
        vm.startPrank(address(core));
        registry.setRedemptionHandler(address(redemptionHandler));
        registry.setLiquidationHandler(address(liquidationHandler));
        registry.setInsurancePool(address(insurancePool));
        registry.setFeeDeposit(address(feeDeposit));
        registry.setRewardHandler(address(rewardHandler));
        stablecoin.setOperator(address(registry), true);
        vm.stopPrank();

        // label all the used addresses for traces
        vm.label(address(tempGov), "Temp Gov");
        vm.label(address(core), "Core");
        vm.label(address(voter), "Voter");
        vm.label(address(govToken), "Gov Token");
        vm.label(address(emissionsController), "Emissions Controller");
        vm.label(address(permaLocker1), "PermaLocker 1");
        vm.label(address(permaLocker2), "PermaLocker 2");
        vm.label(address(staker), "Gov Staker");
        vm.label(address(treasury), "Treasury");
    }

    function deployProtocolContracts() public {
        // stablecoin = new Stablecoin(address(core));
        // registry = new ResupplyRegistry(address(core), address(stablecoin), address(stakingToken));
        deployer = new ResupplyPairDeployer(
            address(core),
            address(registry),
            address(govToken),
            dev
        );

        vm.startPrank(address(core));
        deployer.setCreationCode(type(ResupplyPair).creationCode);
        vm.stopPrank();

        rateCalculator = new InterestRateCalculator(
            "Base",
            2e16 / uint256(365 days),//2%
            2
        );

        oracle = new BasicVaultOracle("Basic Vault Oracle");

        redemptionHandler = new RedemptionHandler(address(core),address(registry));
    }

    function deployRewardsContracts() public {
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
        receiverFactory = new SimpleReceiverFactory(address(core), 
            address(emissionsController), 
            address(simpleReceiverImplementation)
        );

        vm.prank(address(core));
        debtReceiver = SimpleReceiver(receiverFactory.deployNewReceiver("Debt Receiver", new address[](0)));
        vm.prank(address(core));
        insuranceEmissionsReceiver = SimpleReceiver(receiverFactory.deployNewReceiver("Insurance Receiver", new address[](0)));
        
        insurancePool = new InsurancePool(
                address(core), //core
                address(stablecoin),
                rewards,
                address(registry),
                address(insuranceEmissionsReceiver)
        );
        liquidationHandler = new LiquidationHandler(address(core), address(registry), address(insurancePool));

        //seed insurance pool
        stablecoin.transfer(address(insurancePool),1e18);

        ipStableStream = new SimpleRewardStreamer(address(stablecoin), 
            address(registry), 
            address(core), 
            address(insurancePool)
        );

        ipEmissionStream = new SimpleRewardStreamer(address(stakingToken),
            address(registry),
            address(core),
            address(insurancePool)
        );

        //todo queue rewards to pools

        pairEmissionStream = new SimpleRewardStreamer(address(stakingToken), 
            address(registry), 
            address(core), 
            address(0)
        );
        
        feeDeposit = new FeeDeposit(address(core), address(registry), address(stablecoin));
        feeDepositController = new FeeDepositController(address(core), 
            address(registry), 
            address(feeDeposit), 
            1500, 
            500
        );
        //attach fee deposit controller to fee deposit
        vm.prank(address(core));
        feeDeposit.setOperator(address(feeDepositController));

        rewardHandler = new RewardHandler(
            address(core),
            address(registry),
            address(insurancePool), 
            address(debtReceiver),
            address(pairEmissionStream),
            address(ipEmissionStream),
            address(ipStableStream)
        );

        vm.startPrank(address(core));
        //add stablecoin as a reward to gov staker
        staker.addReward(address(stablecoin), address(rewardHandler), uint256(7 days));
        debtReceiver.setApprovedClaimer(address(rewardHandler), true);
        insuranceEmissionsReceiver.setApprovedClaimer(address(rewardHandler), true);
        vm.stopPrank();
    }

    function setInitialEmissionReceivers() public{
        vm.startPrank(address(core));
        //add receivers
        emissionsController.registerReceiver(address(debtReceiver));
        emissionsController.registerReceiver(address(insuranceEmissionsReceiver));
        uint256 debtReceiverId = emissionsController.receiverToId(address(debtReceiver));
        uint256 insuranceReceiverId = emissionsController.receiverToId(address(insuranceEmissionsReceiver));
        //todo other receivers (voting, etc)

        //set weights
        uint256[] memory receivers = new uint256[](2);
        receivers[0] = debtReceiverId;
        receivers[1] = insuranceReceiverId;
        uint256[] memory weights = new uint256[](2);
        weights[0] = 8000;
        weights[1] = 2000;
        emissionsController.setReceiverWeights(receivers,weights);
        vm.stopPrank();
    }

    function deployDaoContracts() public {
        address[3] memory redemptionTokens;
        redemptionTokens[0] = address(new MockToken('PRISMA', 'PRISMA'));
        redemptionTokens[1] = address(new MockToken('yPRISMA', 'yPRISMA'));
        redemptionTokens[2] = address(new MockToken('cvxPRISMA', 'cvxPRISMA'));

        core = new Core(tempGov, epochLength);
        address vestManagerAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this))+2);
        govToken = new GovToken(
            address(core), 
            vestManagerAddress,
            GOV_TOKEN_INITIAL_SUPPLY,
            "Resupply", 
            "RSUP"
        );
        staker = new GovStaker(address(core), address(govToken), 2);
        vestManager = new VestManager(
            address(core), 
            address(govToken),
            BURN_ADDRESS,   // Burn address
            redemptionTokens  // Redemption tokens
        );
        assertEq(address(vestManager), vestManagerAddress);
        
        voter = new Voter(address(core), IGovStaker(address(staker)), 100, 3000);
        stakingToken = govToken;

        vm.prank(address(core));
        core.setVoter(address(voter));
        
        emissionsController = new EmissionsController(
            address(core), 
            address(govToken), 
            getEmissionsSchedule(), 
            3,      // epochs per
            2e16,   // tail rate
            0       // Bootstrap epochs
        );

        vm.prank(address(core));
        govToken.setMinter(address(emissionsController));

        treasury = new Treasury(address(core));
        stablecoin = new Stablecoin(address(core));
        registry = new ResupplyRegistry(address(core), address(stablecoin), address(govToken));
        permaLocker1 = new PermaLocker(address(core), user1, address(staker), address(registry), "Yearn");
        permaLocker2 = new PermaLocker(address(core), user2, address(staker), address(registry), "Convex");
        assertEq(permaLocker1.owner(), user1);
        assertEq(permaLocker2.owner(), user2);

        vm.startPrank(address(core));
        registry.setTreasury(address(treasury));
        registry.setStaker(address(staker));
        vm.stopPrank();
    }

    function deployLendingPair(address _collateral, address _staking, uint256 _stakingId) public returns(ResupplyPair){
        vm.startPrank(deployer.owner());

        address _pairAddress = deployer.deploy(
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
        ResupplyPair pair = ResupplyPair(_pairAddress);
        vm.stopPrank();

        vm.startPrank(address(core));
        registry.addPair(_pairAddress);
        vm.stopPrank();

        return pair;
    }

    function deployDefaultLendingPairs() public{
        deployLendingPair(address(Constants.Mainnet.FRAXLEND_SFRXETH_FRAX), address(0), 0);
        deployLendingPair(address(Constants.Mainnet.CURVELEND_SFRAX_CRVUSD), address(Constants.Mainnet.CONVEX_BOOSTER), uint256(Constants.Mainnet.CURVELEND_SFRAX_CRVUSD_ID));
    }

    function printAddresses() public view {
        console.log("======================================");
        console.log("    Protocol Contracts     ");
        console.log("======================================");
        console.log("Registry: ", address(registry));
        console.log("Deployer: ", address(deployer));
        console.log("govToken: ", address(stakingToken));
        console.log("stablecoin: ", address(stablecoin));
        console.log("insurancePool: ", address(insurancePool));
        console.log("ipStableStream: ", address(ipStableStream));
        console.log("pairEmissionStream: ", address(pairEmissionStream));
        console.log("feeDeposit: ", address(feeDeposit));
        console.log("feeDepositController: ", address(feeDepositController));
        console.log("redemptionHandler: ", address(redemptionHandler));
        console.log("liquidationHandler: ", address(liquidationHandler));
        console.log("rewardHandler: ", address(rewardHandler));
        console.log("debtReceiver: ", address(debtReceiver));
    }

    function getEmissionsSchedule() public view returns (uint256[] memory) {
        uint256[] memory schedule = new uint256[](5);
        schedule[0] = 2 * 10 ** 16;     // 2%
        schedule[1] = 4 * 10 ** 16;     // 4%
        schedule[2] = 6 * 10 ** 16;     // 6%
        schedule[3] = 8 * 10 ** 16;     // 8%
        schedule[4] = 10 * 10 ** 16;    // 10%
        return schedule;
    }

}