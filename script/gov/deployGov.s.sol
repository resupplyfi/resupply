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
    uint88 public randomness; // CREATEX uses the last 88 bits used for randomness
    address public dev = address(0xc4ad);
    address tempGov = address(987);
    address public core;
    address public escrow;
    address public staker;
    address public voter;
    address public govToken;
    address public emissionsController;
    address public vesting;
    address public vestManager;
    address public treasury;
    address public subdao1;
    address public subdao2;
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
        setEthBalance(dev, 10 ether);
        core = deployCore();
        govToken = deployGovToken();
        vesting = deployVesting();
        vestManager = deployVestManager();
        staker = deployGovStaker();
        voter = deployVoter();
        emissionsController = deployEmissionsController();
        treasury = deployTreasury();
        (subdao1, subdao2) = deploySubDaos();
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
        address _vesting = deployer.computeCreateAddress(vm.getNonce(address(deployer))+1);
        bytes memory constructorArgs = abi.encode(
            address(core), 
            address(_vesting), // Next Nonce
            "Resupply", 
            "RSUP"
        );
        bytes memory bytecode = abi.encodePacked(vm.getCode("GovToken.sol:GovToken"), constructorArgs);
        govToken = deployContract(DeployType.CREATE3, salt, bytecode, "GovToken");
        return govToken;
    }

    function deployVesting() public doBroadcast returns (address) {
        bytes memory constructorArgs = abi.encode(
            address(core), 
            address(govToken), 
            365 days // TODO: set vesting duration
        );
        bytes memory bytecode = abi.encodePacked(vm.getCode("Vesting.sol:Vesting"), constructorArgs);
        vesting = deployContract(DeployType.CREATE1,salt, bytecode, "Vesting");
        return vesting;
    }

    function deployVestManager() public doBroadcast returns (address) {
        bytes memory constructorArgs = abi.encode(
            address(core),      // core
            address(vesting),   // vesting contract
            address(0xdead),    // TODO: burn address
            [address(0), address(0), address(0)] // redemption tokens
        );
        bytes memory bytecode = abi.encodePacked(vm.getCode("VestManager.sol:VestManager"), constructorArgs);
        vestManager = deployContract(DeployType.CREATE1,salt, bytecode, "VestManager");
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
            10, 
            2
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

    function deploySubDaos() public doBroadcast returns (address, address) {
        address subdao1Owner = address(1); // TODO: Change this to convex user
        address subdao2Owner = address(2); // TODO: Change this to yearn user
        staker = 0x2791b78390B814f5eBc4d0D3d7F37124Ac2a0b1c;
        bytes memory constructorArgs = abi.encode(
            address(core), 
            subdao1Owner, 
            address(staker), 
            "Convex"
        );
        bytes memory bytecode = abi.encodePacked(vm.getCode("SubDao.sol:SubDao"), constructorArgs);
        subdao1 = deployContract(DeployType.CREATE3, salt, bytecode, "SubDao - Convex");
        constructorArgs = abi.encode(
            address(core), 
            subdao2Owner, 
            address(staker), 
            "Yearn"
        );
        bytecode = abi.encodePacked(vm.getCode("SubDao.sol:SubDao"), constructorArgs);
        subdao2 = deployContract(DeployType.CREATE3, salt, bytecode, "SubDao - Yearn");
        return (subdao1, subdao2);
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
