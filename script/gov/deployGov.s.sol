import { TenderlyHelper } from "../utils/TenderlyHelper.s.sol";
import { CreateXDeployer } from "../utils/CreateXDeployer.s.sol";
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

contract DeployGov is TenderlyHelper, CreateXDeployer {
    address public dev = address(0xc4ad);
    address tempGov = address(987);
    address public core;
    address public escrow;
    address public staker;
    address public voter;
    address public govToken;
    address public emissionsController;
    bytes32 salt; // Use same empty salt for all contracts
    bytes32 computedSalt; // This is the salt transformed by CreateX used in the computeCreate2Address function

    modifier doBroadcast() {
        vm.startBroadcast(dev);
        _;
        vm.stopBroadcast();
    }

    constructor() {
        computedSalt = keccak256(abi.encode(salt));
    }

    function run() public {
        // Array of contract names to deploy
        setEthBalance(dev, 10 ether);
        core = deployCore();
        govToken = deployGovToken();
        staker = deployGovStaker();
        voter = deployVoter();
        emissionsController = deployEmissionsController();
    }

    function deployContract(
        bytes32 _salt,
        bytes memory _bytecode,
        string memory _contractName
    ) internal returns (address) {
        address computedAddress = deployer.computeCreate2Address(computedSalt, keccak256(_bytecode));
        if (address(computedAddress).code.length == 0) {
            computedAddress = deployer.deployCreate2(_salt, _bytecode);
            console.log(string(abi.encodePacked(_contractName, " deployed to:")), address(computedAddress));
        } else {
            console.log(string(abi.encodePacked(_contractName, " already deployed at:")), address(computedAddress));
        }
        return computedAddress;
    }

    function deployCore() public doBroadcast returns (address) {
        bytes memory constructorArgs = abi.encode(tempGov, 1 weeks);
        bytes memory bytecode = abi.encodePacked(vm.getCode("Core.sol:Core"), constructorArgs);
        core = deployContract(salt, bytecode, "Core");
        return core;
    }

    function deployGovToken() public doBroadcast returns (address) {
        bytes memory constructorArgs = abi.encode(address(core), "Resupply", "RSUP");
        bytes memory bytecode = abi.encodePacked(vm.getCode("GovToken.sol:GovToken"), constructorArgs);
        govToken = deployContract(salt, bytecode, "GovToken");
        return govToken;
    }

    function deployGovStaker() public doBroadcast returns (address) {
        bytes memory constructorArgs = abi.encode(address(core), address(govToken), 2);
        bytes memory bytecode = abi.encodePacked(vm.getCode("GovStaker.sol:GovStaker"), constructorArgs);
        staker = deployContract(salt, bytecode, "GovStaker");
        return staker;
    }

    function deployVoter() public doBroadcast returns (address) {
        bytes memory constructorArgs = abi.encode(address(core), IGovStaker(address(staker)), 100, 3000);
        bytes memory bytecode = abi.encodePacked(vm.getCode("Voter.sol:Voter"), constructorArgs);
        voter = deployContract(salt, bytecode, "Voter");
        return voter;
    }

    function deployEmissionsController() public doBroadcast returns (address) {
        bytes memory constructorArgs = abi.encode(
            address(core), 
            address(govToken), 
            getEmissionsSchedule(), 
            10, 
            2
        );
        bytes memory bytecode = abi.encodePacked(vm.getCode("EmissionsController.sol:EmissionsController"), constructorArgs);
        emissionsController = deployContract(salt, bytecode, "EmissionsController");
        return emissionsController;
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
