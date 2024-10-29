import { TenderlyHelper } from "../utils/TenderlyHelper.s.sol";
import { GovStakerEscrow } from "../../src/dao/staking/GovStakerEscrow.sol";
import { GovStaker } from "../../src/dao/staking/GovStaker.sol";
import { GovToken } from "../../src/dao/GovToken.sol";
import { Core } from "../../src/dao/Core.sol";
import { EmissionsController } from "../../src/dao/emissions/EmissionsController.sol";
import { Voter } from "../../src/dao/Voter.sol";
import { IGovStaker } from "../../src/interfaces/IGovStaker.sol";
import { IGovStakerEscrow } from "../../src/interfaces/IGovStakerEscrow.sol";
import "forge-std/console.sol";
import "forge-std/Vm.sol";

contract DeployGov is TenderlyHelper {
    address public dev = address(0xc4ad);
    address tempGov = address(987);
    Core public core;
    GovStakerEscrow public escrow;
    GovStaker public staker;
    Voter public voter;
    GovToken public govToken;
    EmissionsController public emissionsController;

    modifier doBroadcast() {
        vm.startBroadcast(dev);
        _;
        vm.stopBroadcast();
    }

    function run() public {
        // Array of contract names to deploy
        setEthBalance(dev, 100 ether);
        deployContracts();
    }

    function deployContracts() public doBroadcast {
        
        
        uint256 nonce = vm.getNonce(dev);
        address coreAddress = computeCreateAddress(dev, nonce);
        address govTokenAddress = computeCreateAddress(dev, nonce + 1);
        address escrowAddress = computeCreateAddress(dev, nonce + 2);
        address govStakingAddress = computeCreateAddress(dev, nonce + 3);
        
        
        core = new Core(tempGov, 1 weeks);
        govToken = new GovToken(address(core), "Resupply", "RSUP");
        escrow = new GovStakerEscrow(govStakingAddress, govTokenAddress);
        staker = 
            new GovStaker(
                coreAddress, 
                govTokenAddress, 
                escrowAddress, 
                2
        );
        voter = new Voter(coreAddress, IGovStaker(govStakingAddress), 100, 3000);
        
        console.log("govStakingAddress", govStakingAddress);
        console.log("voter", address(voter));
        console.log("govToken", govTokenAddress);
        console.log("escrow", escrowAddress);
        console.log("core", coreAddress);
        emissionsController = new EmissionsController(
            coreAddress, 
            govTokenAddress, 
            getEmissionsSchedule(), 
            10, // epochsPer,
            2 // bootstrapEpochs
        );
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

    function sleep(uint256 _seconds) internal {
        string[] memory inputs = new string[](3);
        inputs[0] = "sleep";
        inputs[1] = toString(_seconds);
        vm.ffi(inputs);
    }
    // Helper for converting uint to string
    function toString(uint256 value) internal pure returns (string memory) {
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
