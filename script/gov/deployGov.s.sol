import { TenderlyHelper } from "../utils/TenderlyHelper.s.sol";
import { GovStakerEscrow } from "../../src/dao/staking/GovStakerEscrow.sol";
import { GovStaker } from "../../src/dao/staking/GovStaker.sol";
import { GovToken } from "../../src/dao/GovToken.sol";
import { Core } from "../../src/dao/Core.sol";
import { EmissionsController } from "../../src/dao/emissions/EmissionsController.sol";
import { Voter } from "../../src/dao/Voter.sol";
import { IGovStaker } from "../../src/interfaces/IGovStaker.sol";
import { IGovStakerEscrow } from "../../src/interfaces/IGovStakerEscrow.sol";
import "../../lib/forge-std/src/console2.sol";
import "../../lib/forge-std/src/console.sol";

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
       

        uint256 nonce = vm.getNonce(dev);
        address coreAddress = vm.computeCreateAddress(dev, nonce);
        address govTokenAddress = vm.computeCreateAddress(dev, nonce + 1);
        address escrowAddress = vm.computeCreateAddress(dev, nonce + 2);
        address govStakingAddress = vm.computeCreateAddress(dev, nonce + 3);
        
        console.log("govStakingAddress", govStakingAddress);
        console.log("voter", address(voter));
        console.log("govToken", govTokenAddress);
        console.log("escrow", escrowAddress);
        console.log("core", coreAddress);

        deployStakingContracts();
        deployOtherContracts();
    }

    function deployStakingContracts() public doBroadcast {
        core = new Core(tempGov, 1 weeks);
        skipBlocks(1);
        govToken = new GovToken(address(core), "Resupply", "RSUP");
        skipBlocks(1);
        escrow = new GovStakerEscrow(address(staker), address(govToken));
        skipBlocks(1);
        staker = 
            new GovStaker(
                address(core), 
                address(govToken), 
                address(escrow), 
                2
        );
    }

    function deployOtherContracts() public doBroadcast {
        voter = new Voter(address(core), IGovStaker(address(staker)), 100, 3000);
        emissionsController = new EmissionsController(
            address(core), 
            address(govToken), 
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
}
