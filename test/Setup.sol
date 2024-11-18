// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.22;

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
    uint256 internal constant DEFAULT_MAX_LTV = 95_000; // 75% with 1e5 precision
    uint256 internal constant DEFAULT_LIQ_FEE = 500; // 5% with 1e5 precision
    uint256 internal constant DEFAULT_BORROW_LIMIT = 5_000_000 * 1e18;
    uint256 internal constant DEFAULT_MINT_FEE = 0; //1e5 prevision
    uint256 internal constant DEFAULT_PROTOCOL_REDEMPTION_FEE = 1e18 / 2; //half
    uint64 internal constant FIFTY_BPS = 158_247_046;
    uint64 internal constant ONE_PERCENT = FIFTY_BPS * 2;
    uint64 internal constant ONE_BPS = FIFTY_BPS / 50;

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
    InterestRateCalculator public rateContract;
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
    MockToken public mockFrax;
    MockToken public mockCrvusd;

    function setUp() public virtual {

        deployDaoContracts();
        deployProtocolContracts();
        deployRewardsContracts();
        deal(address(govToken), user1, 1_000_000 * 10 ** 18);
        vm.prank(user1);
        govToken.approve(address(staker), type(uint256).max);

        mockFrax = new MockToken("Mock FRAX", "mFRAX");
        mockCrvusd = new MockToken("Mock CRVUSD", "mCRVUSD");

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
        stablecoin.setOperator(address(registry), true);
        registry.setTreasury(address(treasury));
        registry.setStaker(address(staker));
        vm.stopPrank();

        rateContract = new InterestRateCalculator(
            "suffix",
            634_195_840,//(2 * 1e16) / 365 / 86400, //2% todo check
            2
        );

        oracle = new BasicVaultOracle("Basic Vault Oracle");

        redemptionHandler = new RedemptionHandler(address(core),address(registry),address(stablecoin));
        liquidationHandler = new LiquidationHandler(address(core), address(registry), address(insurancePool));

        vm.startPrank(address(core));
        registry.setLiquidationHandler(address(liquidationHandler));
        registry.setRedeemer(address(redemptionHandler));
        registry.setInsurancePool(address(insurancePool));
        vm.stopPrank();
    }

    function deployRewardsContracts() public {
        address[] memory rewards = new address[](3);
        rewards[0] = address(govToken);
        rewards[1] = address(mockFrax);
        rewards[2] = address(mockCrvusd);
        insurancePool = new InsurancePool(
            address(core), //core
            address(stablecoin),
            rewards,
            address(registry)
        );

        //seed insurance pool
        stablecoin.transfer(address(insurancePool),1e18);

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
        vm.startPrank(address(core));
        feeDeposit.setOperator(address(feeDepositController));
        vm.stopPrank();

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
        registry.setFeeDeposit(address(feeDeposit));
        registry.setRewardHandler(address(rewardHandler));
        vm.stopPrank();
    }

    function deployDaoContracts() public {
        address[3] memory redemptionTokens;
        redemptionTokens[0] = address(new MockToken('PRISMA', 'PRISMA'));
        redemptionTokens[1] = address(new MockToken('yPRISMA', 'yPRISMA'));
        redemptionTokens[2] = address(new MockToken('cvxPRISMA', 'cvxPRISMA'));

        core = new Core(tempGov, 1 weeks);
        address vestManagerAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this))+2);
        govToken = new GovToken(
            address(core), 
            vestManagerAddress,
            "Resupply", 
            "RSUP"
        );
        staker = new GovStaker(address(core), address(govToken), 2);
        vestManager = new VestManager(
            address(core), 
            address(govToken),
            address(0xdead),   // Burn address
            redemptionTokens,  // Redemption tokens
            365 days           // Time until deadline
        );
        assertEq(address(vestManager), vestManagerAddress);
        
        voter = new Voter(address(core), IGovStaker(address(staker)), 100, 3000);
        stakingToken = govToken;
        
        emissionsController = new EmissionsController(
            address(core), 
            address(govToken), 
            getEmissionsSchedule(), 
            3,      // epochs per
            2e16,   // tail rate
            0       // Bootstrap epochs
        );

        treasury = new Treasury(address(core));
        stablecoin = new Stablecoin(address(core));
        registry = new ResupplyRegistry(address(core), address(stablecoin), address(govToken));
        permaLocker1 = new PermaLocker(address(core), user1, address(staker), address(registry), "Yearn");
        permaLocker2 = new PermaLocker(address(core), user2, address(staker), address(registry), "Convex");
        assertEq(permaLocker1.owner(), user1);
        assertEq(permaLocker2.owner(), user2);
    }

    function deployLendingPair(address _collateral, address _staking, uint256 _stakingId) public returns(ResupplyPair){
        vm.startPrank(deployer.owner());

        address _pairAddress = deployer.deploy(
            abi.encode(
                _collateral,
                address(oracle),
                address(rateContract),
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