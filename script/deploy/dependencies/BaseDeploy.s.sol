import "src/Constants.sol" as Constants;
import { TenderlyHelper } from "script/utils/TenderlyHelper.sol";
import { CreateXHelper } from "script/utils/CreateXHelper.sol";
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
import { ICore } from "src/interfaces/ICore.sol";
import { Utilities } from "src/protocol/Utilities.sol";
import { Swapper } from "src/protocol/Swapper.sol";
import { UnderlyingOracle } from "src/protocol/UnderlyingOracle.sol";

contract BaseDeploy is TenderlyHelper, CreateXHelper {
    // Configs: DAO
    uint256 public constant EPOCH_LENGTH = 1 weeks;
    uint24 public constant STAKER_COOLDOWN_EPOCHS = 2;
    uint256 internal constant GOV_TOKEN_INITIAL_SUPPLY = 60_000_000e18;
    address internal constant FRAX_VEST_TARGET = address(0xB1748C79709f4Ba2Dd82834B8c82D4a505003f27);
    address internal constant BURN_ADDRESS = address(0xdead);
    address internal constant PERMA_STAKER_CONVEX_OWNER = 0xa3C5A1e09150B75ff251c1a7815A07182c3de2FB;
    address internal constant PERMA_STAKER_YEARN_OWNER = 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52;
    string internal constant PERMA_STAKER_CONVEX_NAME = "Convex";
    string internal constant PERMA_STAKER_YEARN_NAME = "Yearn";
    uint256 internal constant DEBT_RECEIVER_WEIGHT = 2500; // pct of weekly emissions to debt receiver
    uint256 internal constant INSURANCE_EMISSIONS_RECEIVER_WEIGHT = 2500; // pct of weekly emissions to insurance emissions receiver
    uint256 internal constant REUSD_LP_INCENTENIVES_RECEIVER_WEIGHT = 5000; // pct of weekly emissions to reUSD lp incentives receiver
    uint256 internal constant VOTER_MIN_CREATE_PROPOSAL_PCT = 100; // 1e4 precision
    uint256 internal constant VOTER_QUORUM_PCT = 3000; // 1e4 precision
    string internal constant GOV_TOKEN_NAME = "Resupply";
    string internal constant GOV_TOKEN_SYMBOL = "RSUP";
    uint256 internal constant EMISSIONS_CONTROLLER_TAIL_RATE = 2e16;
    uint256 internal constant EMISSIONS_CONTROLLER_EPOCHS_PER = 52;
    uint256 internal constant EMISSIONS_CONTROLLER_EPOCHS_PER_YEAR = 2;
    uint256 internal constant EMISSIONS_CONTROLLER_BOOTSTRAP_EPOCHS = 0;

    // Configs: Protocol
    uint256 internal constant DEFAULT_MAX_LTV = 95_000; // 1e5 precision
    uint256 internal constant DEFAULT_LIQ_FEE = 5_000; // 1e5 precision
    uint256 internal constant DEFAULT_MINT_FEE = 0; // 1e5 precision
    uint256 internal DEFAULT_BORROW_LIMIT = 0;
    uint256 internal constant DEFAULT_PROTOCOL_REDEMPTION_FEE = 1e18 / 2; // 1e18 portion of 
    uint256 internal constant FEE_SPLIT_IP = 2500; // 25%
    uint256 internal constant FEE_SPLIT_TREASURY = 500; // 5%
    uint256 internal constant FEE_SPLIT_STAKERS = 7000; // 70%
    address public scrvusd = Constants.Mainnet.CURVE_SCRVUSD;
    address public sfrxusd = Constants.Mainnet.SFRXUSD_ERC20;

    // Base
    uint88 public randomness; // CREATEX uses the last 88 bits used for randomness
    // address public dev = address(0xc4ad);
    address public dev = address(0xFE11a5009f2121622271e7dd0FD470264e076af6);

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
    address public autoStakeCallback;
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
    Utilities public utilities;
    IERC20 public fraxToken = IERC20(address(Constants.Mainnet.FRXUSD_ERC20));
    IERC20 public crvusdToken = IERC20(address(Constants.Mainnet.CURVE_USD_ERC20));
    Swapper public defaultSwapper;
    UnderlyingOracle public underlyingOracle;

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
            uint256 nonce = vm.getNonce(address(createXFactory));
            computedAddress = createXFactory.computeCreateAddress(nonce);
            if (address(computedAddress).code.length == 0) {
                computedAddress = createXFactory.deployCreate(_bytecode);
                console.log(string(abi.encodePacked(_contractName, " deployed to:")), address(computedAddress));
            } else {
                console.log(string(abi.encodePacked(_contractName, " already deployed at:")), address(computedAddress));
            }
        } 
        else if (_deployType == DeployType.CREATE2) {
            computedSalt = keccak256(abi.encode(_salt));
            computedAddress = createXFactory.computeCreate2Address(computedSalt, keccak256(_bytecode));
            if (address(computedAddress).code.length == 0) {
                computedAddress = createXFactory.deployCreate2(_salt, _bytecode);
                console.log(string(abi.encodePacked(_contractName, " deployed to:")), address(computedAddress));
            } else {
                console.log(string(abi.encodePacked(_contractName, " already deployed at:")), address(computedAddress));
            }
        } 
        else if (_deployType == DeployType.CREATE3) {
            randomness = uint88(uint256(keccak256(abi.encode(_contractName))));
            // dev address in first 20 bytes, 1 zero byte, then 11 bytes of randomness
            _salt = bytes32(uint256(uint160(dev)) << 96) | bytes32(uint256(0x00)) << 88| bytes32(uint256(randomness));
            console.logBytes32(_salt);
            computedSalt = keccak256(abi.encode(_salt));
            computedAddress = createXFactory.computeCreate3Address(computedSalt);
            if (address(computedAddress).code.length == 0) {
                computedAddress = createXFactory.deployCreate3(_salt, _bytecode);
                console.log(string(abi.encodePacked(_contractName, " deployed to:")), address(computedAddress));
            } else {
                console.log(string(abi.encodePacked(_contractName, " already deployed at:")), address(computedAddress));
            }
        } 
        return computedAddress;
    }

    function _executeCore(address _target, bytes memory _data) internal returns (bytes memory) {
        return addToBatch(
            core,
            abi.encodeWithSelector(
                ICore.execute.selector, address(_target), _data
            )
        );
    }

    function writeAddressToJson(string memory name, address addr) internal {
        // Format: data/chainId_MM-DD-YYYY.json
        string memory dateStr = formatDate(block.timestamp);
        string memory deploymentPath = string.concat(
            vm.projectRoot(), 
            "/data/deploy_", 
            vm.toString(block.chainid),
            "_",
            dateStr,
            ".json"
        );
        
        string memory existingContent;
        try vm.readFile(deploymentPath) returns (string memory content) {
            existingContent = content;
        } catch {
            existingContent = "{}";
            vm.writeFile(deploymentPath, existingContent);
        }

        // Parse existing content and add new entry
        string memory newContent;
        if (bytes(existingContent).length <= 2) { // If empty or just "{}"
            newContent = string(abi.encodePacked(
                "{\n",
                '    "', name, '": "', vm.toString(addr), '"',
                "\n}"
            ));
        } else {
            // Remove the closing brace, add comma and new entry
            newContent = string(abi.encodePacked(
                substring(existingContent, 0, bytes(existingContent).length - 2), // Remove final \n}
                ',\n',
                '    "', name, '": "', vm.toString(addr), '"',
                "\n}"
            ));
        }
        
        vm.writeFile(deploymentPath, newContent);
    }

    function substring(string memory str, uint256 startIndex, uint256 endIndex) private pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        bytes memory result = new bytes(endIndex - startIndex);
        for (uint256 i = startIndex; i < endIndex; i++) {
            result[i - startIndex] = strBytes[i];
        }
        return string(result);
    }

    function formatDate(uint256 timestamp) internal pure returns (string memory) {
        uint256 year;
        uint256 month;
        uint256 day;

        // Calculate the number of days since unix ts = 0
        uint256 daysSinceEpoch = timestamp / 86400;

        // Calculate the year
        year = 1970;
        while (daysSinceEpoch >= 365) {
            if (isLeapYear(year)) {
                if (daysSinceEpoch >= 366) {
                    daysSinceEpoch -= 366;
                    year++;
                }
            } else {
                daysSinceEpoch -= 365;
                year++;
            }
        }

        // Calculate the month and day
        uint256[12] memory monthDays = [uint256(31), 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
        if (isLeapYear(year)) {
            monthDays[1] = 29; // February has 29 days in a leap year
        }

        month = 1;
        for (uint256 i = 0; i < 12; i++) {
            if (daysSinceEpoch < monthDays[i]) {
                day = daysSinceEpoch + 1;
                break;
            } else {
                daysSinceEpoch -= monthDays[i];
                month++;
            }
        }

        // Format date
        return string(abi.encodePacked(
            month < 10 ? "0" : "", uintToString(month), "-",
            day < 10 ? "0" : "", uintToString(day), "-",
            uintToString(year)
        ));
    }

    function isLeapYear(uint256 year) internal pure returns (bool) {
        return (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
    }

    function uintToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
