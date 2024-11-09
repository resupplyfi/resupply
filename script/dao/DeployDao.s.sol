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
import "../../lib/forge-std/src/console.sol";

contract DeployDao is TenderlyHelper, CreateXDeployer {
    uint88 public randomness; // CREATEX uses the last 88 bits used for randomness
    address public dev = address(0xc4ad);
    address tempGov = address(987);
    address public core;
    address public escrow;
    address public staker;
    address public voter;
    address public govToken;
    address public emissionsController;
    address public vestManager;
    address public treasury;
    address public permaLocker1;
    address public permaLocker2;
    address public guardianOperator;
    address public guardianAuthHook;
    bytes32 salt; // Use same empty salt for all contracts

    modifier doBroadcast() {
        vm.startBroadcast(dev);
        _;
        vm.stopBroadcast();
    }

    enum DeployType {
        CREATE1,
        CREATE2,
        CREATE3
    }

    function run() public {
        bool isTestNet = true; // TODO: Change this to false
        setEthBalance(dev, 10 ether);
        core = deployCore();
        govToken = deployGovToken();
        vestManager = deployVestManager(isTestNet);
        staker = deployGovStaker();
        voter = deployVoter();
        emissionsController = deployEmissionsController();
        treasury = deployTreasury();
        (permaLocker1, permaLocker2) = deployPermaLockers();
        guardianOperator = deployGuardianOperator();
        guardianAuthHook = deployGuardianAuthHook();
    }

    function deployContract(
        DeployType _deployType,
        bytes32 _salt,
        bytes memory _bytecode,
        string memory _contractName
    ) internal returns (address) {
        address computedAddress;
        bytes32 computedSalt;
        if (_deployType == DeployType.CREATE1) {
            uint256 nonce = vm.getNonce(address(deployer));
            computedAddress = deployer.computeCreateAddress(nonce);
            if (address(computedAddress).code.length == 0) {
                computedAddress = deployer.deployCreate(_bytecode);
                console.log(string(abi.encodePacked(_contractName, " deployed to:")), address(computedAddress));
            } else {
                console.log(string(abi.encodePacked(_contractName, " already deployed at:")), address(computedAddress));
            }
        } 
        else if (_deployType == DeployType.CREATE2) {
            computedSalt = keccak256(abi.encode(_salt));
            computedAddress = deployer.computeCreate2Address(computedSalt, keccak256(_bytecode));
            if (address(computedAddress).code.length == 0) {
                computedAddress = deployer.deployCreate2(_salt, _bytecode);
                console.log(string(abi.encodePacked(_contractName, " deployed to:")), address(computedAddress));
            } else {
                console.log(string(abi.encodePacked(_contractName, " already deployed at:")), address(computedAddress));
            }
        } 
        else if (_deployType == DeployType.CREATE3) {
            randomness = uint88(uint256(keccak256(abi.encode(_contractName))));
            _salt = bytes32(uint256(uint160(dev) + randomness));
            computedSalt = keccak256(abi.encode(_salt));
            computedAddress = deployer.computeCreate3Address(computedSalt);
            if (address(computedAddress).code.length == 0) {
                computedAddress = deployer.deployCreate3(_salt, _bytecode);
                console.log(string(abi.encodePacked(_contractName, " deployed to:")), address(computedAddress));
            } else {
                console.log(string(abi.encodePacked(_contractName, " already deployed at:")), address(computedAddress));
            }
        } 
        return computedAddress;
    }

    function deployCore() public doBroadcast returns (address) {
        bytes memory constructorArgs = abi.encode(tempGov, 1 weeks);
        bytes memory bytecode = abi.encodePacked(vm.getCode("Core.sol:Core"), constructorArgs);
        core = deployContract(DeployType.CREATE3, salt, bytecode, "Core");
        return core;
    }

    function deployGovToken() public doBroadcast returns (address) {
        address _vestManagerAddress = deployer.computeCreateAddress(vm.getNonce(address(deployer))+1);
        bytes memory constructorArgs = abi.encode(
            address(core), 
            _vestManagerAddress, // Next Nonce
            "Resupply", 
            "RSUP"
        );
        bytes memory bytecode = abi.encodePacked(vm.getCode("GovToken.sol:GovToken"), constructorArgs);
        govToken = deployContract(DeployType.CREATE3, salt, bytecode, "GovToken");
        return govToken;
    }

    function deployVestManager(bool _isTestNet) public doBroadcast returns (address) {
        bytes memory constructorArgs = abi.encode(
            address(core),      // core
            address(govToken),  // govToken
            address(0xdead),    // TODO: set burn address
            [                   // redemption tokens
                0xdA47862a83dac0c112BA89c6abC2159b95afd71C, // prisma 
                0xe3668873D944E4A949DA05fc8bDE419eFF543882, // yprisma
                0x34635280737b5BFe6c7DC2FC3065D60d66e78185  // cvxprisma
            ],
            365 days           // TODO: Set time until deadline
        );
        bytes memory bytecode;
        if (_isTestNet) {
            bytecode = abi.encodePacked(vm.getCode("VestManagerTEST.sol:VestManagerTEST"), constructorArgs);
        }
        else{
            bytecode = abi.encodePacked(vm.getCode("VestManager.sol:VestManager"), constructorArgs);
        }
        
        vestManager = deployContract(DeployType.CREATE1, salt, bytecode, "VestManager");
        return vestManager;
    }

    function deployGovStaker() public doBroadcast returns (address) {
        bytes memory constructorArgs = abi.encode(address(core), address(govToken), 2);
        bytes memory bytecode = abi.encodePacked(vm.getCode("GovStaker.sol:GovStaker"), constructorArgs);
        staker = deployContract(DeployType.CREATE1, salt, bytecode, "GovStaker");
        return staker;
    }

    function deployVoter() public doBroadcast returns (address) {
        bytes memory constructorArgs = abi.encode(address(core), IGovStaker(address(staker)), 100, 3000);
        bytes memory bytecode = abi.encodePacked(vm.getCode("Voter.sol:Voter"), constructorArgs);
        voter = deployContract(DeployType.CREATE1, salt, bytecode, "Voter");
        return voter;
    }

    function deployEmissionsController() public doBroadcast returns (address) {
        bytes memory constructorArgs = abi.encode(
            address(core), 
            address(govToken), 
            getEmissionsSchedule(), 
            3,       // epochs per
            2e16,    // tail rate 2%
            2        // Bootstrap epochs
        );
        bytes memory bytecode = abi.encodePacked(vm.getCode("EmissionsController.sol:EmissionsController"), constructorArgs);
        emissionsController = deployContract(DeployType.CREATE1,salt, bytecode, "EmissionsController");
        return emissionsController;
    }

    function deployTreasury() public doBroadcast returns (address) {
        bytes memory constructorArgs = abi.encode(address(core));
        bytes memory bytecode = abi.encodePacked(vm.getCode("Treasury.sol:Treasury"), constructorArgs);
        treasury = deployContract(DeployType.CREATE1, salt, bytecode, "Treasury");
        return treasury;
    }

    function deployPermaLockers() public doBroadcast returns (address, address) {
        address permaLocker1Owner = address(1); // TODO: Change this to convex user
        address permaLocker2Owner = address(2); // TODO: Change this to yearn user
        address registry = address(0);          // TODO: Change this to ResupplyRegistry
        bytes memory constructorArgs = abi.encode(
            address(core), 
            permaLocker1Owner, 
            address(staker), 
            registry,
            "Convex"
        );
        bytes memory bytecode = abi.encodePacked(vm.getCode("PermaLocker.sol:PermaLocker"), constructorArgs);
        permaLocker1 = deployContract(DeployType.CREATE3, salt, bytecode, "PermaLocker - Convex");
        constructorArgs = abi.encode(
            address(core), 
            permaLocker2Owner, 
            address(staker),
            registry, 
            "Yearn"
        );
        bytecode = abi.encodePacked(vm.getCode("PermaLocker.sol:PermaLocker"), constructorArgs);
        permaLocker2 = deployContract(DeployType.CREATE3, salt, bytecode, "PermaLocker - Yearn");
        return (permaLocker1, permaLocker2);
    }

    function deployGuardianOperator() public doBroadcast returns (address) {
        bytes memory constructorArgs = abi.encode(address(core), address(govToken));
        bytes memory bytecode = abi.encodePacked(vm.getCode("GuardianOperator.sol:GuardianOperator"), constructorArgs);
        guardianOperator = deployContract(DeployType.CREATE1, salt, bytecode, "GuardianOperator");
        return guardianOperator;
    }

    function deployGuardianAuthHook() public doBroadcast returns (address) {
        bytes memory constructorArgs = abi.encode(address(core), address(govToken));
        bytes memory bytecode = abi.encodePacked(vm.getCode("GuardianAuthHook.sol:GuardianAuthHook"), constructorArgs);
        guardianAuthHook = deployContract(DeployType.CREATE1, salt, bytecode, "GuardianAuthHook");
        return guardianAuthHook;
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
