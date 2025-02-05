import { TenderlyHelper } from "script/utils/TenderlyHelper.s.sol";
import { CreateXDeployer } from "script/utils/CreateXDeployer.s.sol";
import { console } from "forge-std/console.sol";
import { ResupplyPairDeployer } from "src/protocol/ResupplyPairDeployer.sol";
import { ResupplyPair } from "src/protocol/ResupplyPair.sol";
import { InterestRateCalculator } from "src/protocol/InterestRateCalculator.sol";
import { BasicVaultOracle } from "src/protocol/BasicVaultOracle.sol";
import { RedemptionHandler } from "src/protocol/RedemptionHandler.sol";
import { LiquidationHandler } from "src/protocol/LiquidationHandler.sol";
import { RewardHandler } from "src/protocol/RewardHandler.sol";
import { FeeDeposit } from "src/protocol/FeeDeposit.sol";
import { FeeDepositController } from "src/protocol/FeeDepositController.sol";
import { SimpleRewardStreamer } from "src/protocol/SimpleRewardStreamer.sol";
import { InsurancePool } from "src/protocol/InsurancePool.sol";
import { SimpleReceiverFactory } from "src/dao/emissions/receivers/SimpleReceiverFactory.sol";
import { SimpleReceiver } from "src/dao/emissions/receivers/SimpleReceiver.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { Stablecoin } from "src/protocol/Stablecoin.sol";

contract BaseDeploy is TenderlyHelper, CreateXDeployer {
    // Configs: DAO
    uint256 public constant EPOCH_LENGTH = 1 weeks;
    uint256 public constant STAKER_COOLDOWN_EPOCHS = 2;
    uint256 internal constant GOV_TOKEN_INITIAL_SUPPLY = 60_000_000e18;
    address internal constant FRAX_VEST_TARGET = address(0xB1748C79709f4Ba2Dd82834B8c82D4a505003f27);
    address internal constant BURN_ADDRESS = address(0xdead);
    address internal constant PERMA_STAKER1_OWNER = address(1);
    address internal constant PERMA_STAKER2_OWNER = address(2);
    string internal constant PERMA_STAKER1_NAME = "Convex";
    string internal constant PERMA_STAKER2_NAME = "Yearn";

    // Configs: Protocol
    uint256 internal constant DEFAULT_MAX_LTV = 95_000; // 95% with 1e5 precision
    uint256 internal constant DEFAULT_LIQ_FEE = 5_000; // 5% with 1e5 precision
    uint256 internal constant DEFAULT_BORROW_LIMIT = 5_000_000 * 1e18;
    uint256 internal constant DEFAULT_MINT_FEE = 0; //1e5 prevision
    uint256 internal constant DEFAULT_PROTOCOL_REDEMPTION_FEE = 1e18 / 2; //half
    uint64 internal constant FIFTY_BPS = 158_247_046;
    uint64 internal constant ONE_PERCENT = FIFTY_BPS * 2;
    uint64 internal constant ONE_BPS = FIFTY_BPS / 50;

    // Base
    uint88 public randomness; // CREATEX uses the last 88 bits used for randomness
    address public dev = address(0xc4ad);

    // DAO Contracts
    address public core;
    address public escrow;
    address public staker;
    address public voter;
    address public govToken;
    address public emissionsController;
    address public vestManager;
    address public treasury;
    address public permaStaker1;
    address public permaStaker2;
    IResupplyRegistry public registry;
    Stablecoin public stablecoin;

    // Protocol Contracts
    BasicVaultOracle public oracle;
    InterestRateCalculator public rateCalculator;
    ResupplyPairDeployer public pairDeployer;
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


    // TODO: Guardiant things
    bytes32 salt; // Use same empty salt for all contracts


    modifier doBroadcast(address _sender) {
        vm.startBroadcast(_sender);
        _;
        vm.stopBroadcast();
    }

    enum DeployType {
        CREATE1,
        CREATE2,
        CREATE3
    }

    function deployContract(
        DeployType _deployType,
        bytes32 _salt,
        bytes memory _bytecode,
        string memory _contractName
    ) internal returns (address) {
        address computedAddress;
        bytes32 computedSalt;
        console.log("Deploying contract:", _contractName, " .... ");
        if (_deployType == DeployType.CREATE1) {
            uint256 nonce = vm.getNonce(address(createXDeployer));
            computedAddress = createXDeployer.computeCreateAddress(nonce);
            if (address(computedAddress).code.length == 0) {
                computedAddress = createXDeployer.deployCreate(_bytecode);
                console.log(string(abi.encodePacked(_contractName, " deployed to:")), address(computedAddress));
            } else {
                console.log(string(abi.encodePacked(_contractName, " already deployed at:")), address(computedAddress));
            }
        } 
        else if (_deployType == DeployType.CREATE2) {
            computedSalt = keccak256(abi.encode(_salt));
            computedAddress = createXDeployer.computeCreate2Address(computedSalt, keccak256(_bytecode));
            if (address(computedAddress).code.length == 0) {
                computedAddress = createXDeployer.deployCreate2(_salt, _bytecode);
                console.log(string(abi.encodePacked(_contractName, " deployed to:")), address(computedAddress));
            } else {
                console.log(string(abi.encodePacked(_contractName, " already deployed at:")), address(computedAddress));
            }
        } 
        else if (_deployType == DeployType.CREATE3) {
            randomness = uint88(uint256(keccak256(abi.encode(_contractName))));
            _salt = bytes32(uint256(uint160(dev) + randomness));
            computedSalt = keccak256(abi.encode(_salt));
            computedAddress = createXDeployer.computeCreate3Address(computedSalt);
            if (address(computedAddress).code.length == 0) {
                computedAddress = createXDeployer.deployCreate3(_salt, _bytecode);
                console.log(string(abi.encodePacked(_contractName, " deployed to:")), address(computedAddress));
            } else {
                console.log(string(abi.encodePacked(_contractName, " already deployed at:")), address(computedAddress));
            }
        } 
        return computedAddress;
    }
}
