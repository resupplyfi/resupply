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
import { DeploymentConfig } from "script/deploy/dependencies/DeploymentConfig.sol";

contract BaseDeploy is TenderlyHelper, CreateXHelper {
    address public deployer = DeploymentConfig.DEPLOYER;
    uint256 public defaultBorrowLimit = DeploymentConfig.DEFAULT_BORROW_LIMIT;
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
