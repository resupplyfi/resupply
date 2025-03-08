import { GovStakerEscrow } from "src/dao/staking/GovStakerEscrow.sol";
import { BaseDeploy } from "./BaseDeploy.s.sol";
import { IGovStakerEscrow } from "src/interfaces/IGovStakerEscrow.sol";
import { console2 } from "forge-std/console2.sol";
import { console } from "forge-std/console.sol";
import { IGovStaker } from "src/interfaces/IGovStaker.sol";
import { VestManagerHarness } from "src/helpers/VestManagerHarness.sol";
import { VestManager } from "src/dao/tge/VestManager.sol";
import { GovStaker } from "src/dao/staking/GovStaker.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { Stablecoin } from "src/protocol/Stablecoin.sol";

contract DeployResupplyDao is BaseDeploy {
    bool constant DEBUG = false;
    function deployDaoContracts() public {
        core = deployCore();
        if (DEBUG) console2.log("Gas used", totalGasUsed);
        govToken = deployGovToken(); // WARNING: DO NOT MOVE! Otherwise the address calculated will be wrong.
        if (DEBUG) console2.log("Gas used", totalGasUsed);
        vestManager = deployVestManager(); // WARNING: DO NOT MOVE! Otherwise the address calculated will be wrong.
        if (DEBUG) console2.log("Gas used", totalGasUsed);
        stablecoin = Stablecoin(deployStablecoin());
        if (DEBUG) console2.log("Gas used", totalGasUsed);
        registry = IResupplyRegistry(deployRegistry());
        if (DEBUG) console2.log("Gas used", totalGasUsed);
        staker = deployGovStaker();
        if (DEBUG) console2.log("Gas used", totalGasUsed);
        autoStakeCallback = deployAutoStakeCallback();
        if (DEBUG) console2.log("Gas used", totalGasUsed);
        voter = deployVoter();
        if (DEBUG) console2.log("Gas used", totalGasUsed);
        emissionsController = deployEmissionsController();
        if (DEBUG) console2.log("Gas used", totalGasUsed);
        treasury = deployTreasury();
        if (DEBUG) console2.log("Gas used", totalGasUsed);
    }

    function deployAutoStakeCallback() public returns (address) {
        bytes32 salt = buildGuardedSalt(dev, true, false, uint88(uint256(keccak256(bytes("AutoStakeCallback")))));
        address predictedAddress = computeCreate3AddressFromSaltPreimage(salt, dev, true, false);
        if (addressHasCode(predictedAddress)) return predictedAddress;
        bytes memory constructorArgs = abi.encode(address(core), address(staker), address(vestManager));
        bytes memory bytecode = abi.encodePacked(vm.getCode("AutoStakeCallback.sol:AutoStakeCallback"), constructorArgs);
        addToBatch(
            address(createXFactory),
            encodeCREATE3Deployment(salt, bytecode)
        );
        console.log("AutoStakeCallback deployed to", predictedAddress);
        writeAddressToJson("AUTO_STAKE_CALLBACK", predictedAddress);
        return predictedAddress;
    }

    function deployStablecoin() public returns (address) {
        bytes memory constructorArgs = abi.encode(address(core));
        bytes32 salt = 0xfe11a5009f2121622271e7dd0fd470264e076af6007d4a011e1aea8d0220315d;
        address predictedAddress = computeCreate3AddressFromSaltPreimage(salt, dev, true, false);
        if (addressHasCode(predictedAddress)) return predictedAddress;
        bytes memory bytecode = abi.encodePacked(vm.getCode("Stablecoin.sol:Stablecoin"), constructorArgs);
        addToBatch(
            address(createXFactory),
            encodeCREATE3Deployment(salt, bytecode)
        );
        console.log("Stablecoin deployed to", predictedAddress);
        writeAddressToJson("STABLECOIN", predictedAddress);
        return predictedAddress;
    }

    function deployRegistry() public returns (address) {
        bytes32 salt = 0xfe11a5009f2121622271e7dd0fd470264e076af60035199030be4b0602635825;
        address predictedAddress = computeCreate3AddressFromSaltPreimage(salt, dev, true, false);
        if (addressHasCode(predictedAddress)) return predictedAddress;
        bytes memory constructorArgs = abi.encode(address(core), address(stablecoin), address(govToken));
        bytes memory bytecode = abi.encodePacked(vm.getCode("ResupplyRegistry.sol:ResupplyRegistry"), constructorArgs);
        addToBatch(
            address(createXFactory),
            encodeCREATE3Deployment(salt, bytecode)
        );
        console.log("Registry deployed to", predictedAddress);
        writeAddressToJson("REGISTRY", predictedAddress);
        return predictedAddress;
    }

    function deployCore() public returns (address) {
        bytes32 salt = 0xfe11a5009f2121622271e7dd0fd470264e076af60075182fe1eff89e02ce3cff;
        address predictedAddress = computeCreate3AddressFromSaltPreimage(salt, dev, true, false);
        bytes memory constructorArgs = abi.encode(dev, EPOCH_LENGTH);
        bytes memory bytecode = abi.encodePacked(vm.getCode("Core.sol:Core"), constructorArgs);
        addToBatch(
            address(createXFactory),
            encodeCREATE3Deployment(salt, bytecode)
        );
        console.log("Core deployed to", predictedAddress);
        writeAddressToJson("CORE", predictedAddress);
        return predictedAddress;
    }

    function deployGovToken() public returns (address) {
        bytes32 vmSalt = 0xfe11a5009f2121622271e7dd0fd470264e076af6000cc7db37bf283f00158d19;
        address _vestManagerAddress = computeCreate3AddressFromSaltPreimage(vmSalt, dev, true, false);
        bytes32 salt = 0xfe11a5009f2121622271e7dd0fd470264e076af6007817270164e1790196c4f0;
        address predictedAddress = computeCreate3AddressFromSaltPreimage(salt, dev, true, false);
        if (addressHasCode(predictedAddress)) return predictedAddress;
        bytes memory constructorArgs = abi.encode(
            address(core),
            _vestManagerAddress,
            GOV_TOKEN_INITIAL_SUPPLY,
            "Resupply", 
            "RSUP"
        );
        bytes memory bytecode = abi.encodePacked(vm.getCode("GovToken.sol:GovToken"), constructorArgs);
        addToBatch(
            address(createXFactory),
            encodeCREATE3Deployment(salt, bytecode)
        );
        console.log("GovToken deployed to", predictedAddress);
        writeAddressToJson("GOV_TOKEN", predictedAddress);
        return predictedAddress;
    }

    function deployVestManager() public returns (address) {
        bytes32 salt = 0xfe11a5009f2121622271e7dd0fd470264e076af6000cc7db37bf283f00158d19;
        address predictedAddress = computeCreate3AddressFromSaltPreimage(salt, dev, true, false);
        if (addressHasCode(predictedAddress)) return predictedAddress;
        bytes memory constructorArgs = abi.encode(
            address(core),
            address(govToken), 
            address(BURN_ADDRESS), 
            [
                0xdA47862a83dac0c112BA89c6abC2159b95afd71C, // prisma 
                0xe3668873D944E4A949DA05fc8bDE419eFF543882, // yprisma
                0x34635280737b5BFe6c7DC2FC3065D60d66e78185  // cvxprisma
            ]
        );
        bytes memory bytecode = (
            deployMode != DeployMode.MAINNET ?
                abi.encodePacked(vm.getCode("VestManagerHarness.sol:VestManagerHarness"), constructorArgs) :
                abi.encodePacked(vm.getCode("VestManager.sol:VestManager"), constructorArgs)
        );
        addToBatch(
            address(createXFactory),
            encodeCREATE3Deployment(salt, bytecode)
        );
        console.log("VestManager deployed to", predictedAddress);
        writeAddressToJson("VEST_MANAGER", predictedAddress);
        return predictedAddress;
    }

    function deployGovStaker() public returns (address) {
        bytes32 salt = 0xfe11a5009f2121622271e7dd0fd470264e076af600ac101fb2686a8c0015ef91;
        address predictedAddress = computeCreate3AddressFromSaltPreimage(salt, dev, true, false);
        if (addressHasCode(predictedAddress)) return predictedAddress;
        bytes memory constructorArgs = abi.encode(
            address(core),
            address(registry),
            address(govToken), 
            uint24(STAKER_COOLDOWN_EPOCHS)
        );
        bytes memory bytecode = abi.encodePacked(vm.getCode("GovStaker.sol:GovStaker"), constructorArgs);
        addToBatch(
            address(createXFactory),
            encodeCREATE3Deployment(salt, bytecode)
        );
        console.log("GovStaker deployed to", predictedAddress);
        writeAddressToJson("GOV_STAKER", predictedAddress);
        return predictedAddress;
    }

    function deployVoter() public returns (address) {
        bytes32 salt = 0xfe11a5009f2121622271e7dd0fd470264e076af60067a2e41ad02c1700e3f506;
        address predictedAddress = computeCreate3AddressFromSaltPreimage(salt, dev, true, false);
        if (addressHasCode(predictedAddress)) return predictedAddress;
        bytes memory constructorArgs = abi.encode(address(core), IGovStaker(address(staker)), 100, 3000);
        bytes memory bytecode = abi.encodePacked(vm.getCode("Voter.sol:Voter"), constructorArgs);
        addToBatch(
            address(createXFactory),
            encodeCREATE3Deployment(salt, bytecode)
        );
        console.log("Voter deployed to", predictedAddress);
        writeAddressToJson("VOTER", predictedAddress);
        return predictedAddress;
    }

    function deployEmissionsController() public returns (address) {
        bytes32 salt = 0xfe11a5009f2121622271e7dd0fd470264e076af60045a2b62cd5fec002054177;
        address predictedAddress = computeCreate3AddressFromSaltPreimage(salt, dev, true, false);
        if (addressHasCode(predictedAddress)) return predictedAddress;
        bytes memory constructorArgs = abi.encode(
            address(core), 
            address(govToken), 
            getEmissionsSchedule(), 
            3,       // epochs per
            2e16,    // tail rate 2%
            2        // Bootstrap epochs
        );
        bytes memory bytecode = abi.encodePacked(vm.getCode("EmissionsController.sol:EmissionsController"), constructorArgs);
        addToBatch(
            address(createXFactory),
            encodeCREATE3Deployment(salt, bytecode)
        );
        console.log("EmissionsController deployed to", predictedAddress);
        writeAddressToJson("EMISSIONS_CONTROLLER", predictedAddress);
        return predictedAddress;
    }

    function deployTreasury() public returns (address) {
        bytes32 salt = 0xfe11a5009f2121622271e7dd0fd470264e076af6006bbac7a598ad55036e9c9c;
        address predictedAddress = computeCreate3AddressFromSaltPreimage(salt, dev, true, false);
        if (addressHasCode(predictedAddress)) return predictedAddress;
        bytes memory constructorArgs = abi.encode(address(core));
        bytes memory bytecode = abi.encodePacked(vm.getCode("Treasury.sol:Treasury"), constructorArgs);
        addToBatch(
            address(createXFactory),
            encodeCREATE3Deployment(salt, bytecode)
        );
        console.log("Treasury deployed to", predictedAddress);
        writeAddressToJson("TREASURY", predictedAddress);
        return predictedAddress;
    }

    function deployPermaStakers() public returns (address, address) {
        bytes32 salt = 0xfe11a5009f2121622271e7dd0fd470264e076af600847421d8997e1100819f27;
        bytes memory constructorArgs = abi.encode(
            address(core),
            address(registry),
            PERMA_STAKER_CONVEX_OWNER,
            address(vestManager),
            PERMA_STAKER_CONVEX_NAME
        );
        bytes memory bytecode = abi.encodePacked(vm.getCode("PermaStaker.sol:PermaStaker"), constructorArgs);
        
        address predictedAddress1 = computeCreate3AddressFromSaltPreimage(salt, dev, true, false);
        if (!addressHasCode(predictedAddress1)) {
            addToBatch(
                address(createXFactory),
                encodeCREATE3Deployment(salt, bytecode)
            );
        }
        console.log("PermaStaker Convex deployed to", predictedAddress1);
        writeAddressToJson("PERMA_STAKER_CONVEX", predictedAddress1);
        constructorArgs = abi.encode(
            address(core),
            address(registry),
            PERMA_STAKER_YEARN_OWNER, 
            address(vestManager),
            PERMA_STAKER_YEARN_NAME
        );
        bytecode = abi.encodePacked(vm.getCode("PermaStaker.sol:PermaStaker"), constructorArgs);
        salt = 0xfe11a5009f2121622271e7dd0fd470264e076af6005045c04e56a6ce00770772;
        address predictedAddress2 = computeCreate3AddressFromSaltPreimage(salt, dev, true, false);
        if (!addressHasCode(predictedAddress2)) {
            addToBatch(
                address(createXFactory),
                encodeCREATE3Deployment(salt, bytecode)
            );
        }
        
        console.log("PermaStaker Yearn deployed to", predictedAddress2);
        writeAddressToJson("PERMA_STAKER_YEARN", predictedAddress2);
        return (predictedAddress1, predictedAddress2);
    }

    function getEmissionsSchedule() public pure returns (uint256[] memory) {
        uint256[] memory schedule = new uint256[](5);
        schedule[0] = 2 * 10 ** 16;     // 2%
        schedule[1] = 4 * 10 ** 16;     // 4%
        schedule[2] = 6 * 10 ** 16;     // 6%
        schedule[3] = 8 * 10 ** 16;     // 8%
        schedule[4] = 10 * 10 ** 16;    // 10%
        return schedule;
    }
}
