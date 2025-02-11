import { GovStakerEscrow } from "src/dao/staking/GovStakerEscrow.sol";
import { BaseDeploy } from "./BaseDeploy.s.sol";
import { IGovStakerEscrow } from "src/interfaces/IGovStakerEscrow.sol";
import { console } from "forge-std/console.sol";
import { IGovStaker } from "src/interfaces/IGovStaker.sol";
import { VestManagerHarness } from "src/helpers/VestManagerHarness.sol";
import { VestManager } from "src/dao/tge/VestManager.sol";
import { GovStaker } from "src/dao/staking/GovStaker.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { Stablecoin } from "src/protocol/Stablecoin.sol";

contract DeployResupplyDao is BaseDeploy {

    function deployDaoContracts(bool isTestNet) public {
        core = deployCore();
        govToken = deployGovToken(isTestNet); // WARNING: DO NOT MOVE! Otherwise the address calculated will be wrong.
        vestManager = deployVestManager(isTestNet); // WARNING: DO NOT MOVE! Otherwise the address calculated will be wrong.
        stablecoin = Stablecoin(deployStablecoin());
        registry = IResupplyRegistry(deployRegistry());
        staker = deployGovStaker();
        voter = deployVoter();
        emissionsController = deployEmissionsController();
        treasury = deployTreasury();
    }

    function deployStablecoin() public returns (address) {
        bytes memory constructorArgs = abi.encode(address(core));
        bytes32 salt = buildGuardedSalt(
            dev, 
            true,   // enablePermissionedDeploy
            false,  // enableCrossChainProtection
            0
        );
        address predictedAddress = computeCreate3AddressFromSaltPreimage(salt, dev, true, false);
        if (addressHasCode(predictedAddress)) return predictedAddress;
        bytes memory bytecode = abi.encodePacked(vm.getCode("Stablecoin.sol:Stablecoin"), constructorArgs);
        addToBatch(
            address(createXFactory),
            encodeCREATE3Deployment(salt, bytecode)
        );
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
        return predictedAddress;
    }

    function deployCore() public returns (address) {
        bytes32 salt = 0xfe11a5009f2121622271e7dd0fd470264e076af60075182fe1eff89e02ce3cff;
        address predictedAddress = computeCreate3AddressFromSaltPreimage(salt, dev, true, false);
        if (addressHasCode(predictedAddress)) return predictedAddress;
        bytes memory constructorArgs = abi.encode(dev, EPOCH_LENGTH);
        bytes memory bytecode = abi.encodePacked(vm.getCode("Core.sol:Core"), constructorArgs);
        addToBatch(
            address(createXFactory),
            encodeCREATE3Deployment(salt, bytecode)
        );
        return predictedAddress;
    }

    function deployGovToken(bool _isTestNet) public returns (address) {
        bytes32 vmSalt = 0xfe11a5009f2121622271e7dd0fd470264e076af6000cc7db37bf283f00158d19;
        address _vestManagerAddress = computeCreate3AddressFromSaltPreimage(vmSalt, dev, true, false);
        
        bytes32 salt = 0xfe11a5009f2121622271e7dd0fd470264e076af6007817270164e1790196c4f0;
        address predictedAddress = computeCreate3AddressFromSaltPreimage(salt, dev, true, false);
        console.log("GovToken predictedAddress", predictedAddress);
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
        return predictedAddress;
    }

    function deployVestManager(bool _isTestNet) public returns (address) {
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
            _isTestNet ?
                abi.encodePacked(vm.getCode("VestManagerHarness.sol:VestManagerHarness"), constructorArgs) :
                abi.encodePacked(vm.getCode("VestManager.sol:VestManager"), constructorArgs)
        );
        addToBatch(
            address(createXFactory),
            encodeCREATE3Deployment(salt, bytecode)
        );
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
        return predictedAddress;
    }

    function deployPermaStakers() public returns (address, address) {
        bytes memory constructorArgs = abi.encode(
            address(core), 
            PERMA_STAKER1_OWNER,
            address(registry),
            address(vestManager),
            PERMA_STAKER1_NAME
        );
        bytes memory bytecode = abi.encodePacked(vm.getCode("PermaStaker.sol:PermaStaker"), constructorArgs);
        permaStaker1 = deployContract(DeployType.CREATE3, salt, bytecode, "PermaStaker - Convex");
        constructorArgs = abi.encode(
            address(core), 
            PERMA_STAKER2_OWNER,
            address(registry), 
            address(vestManager),
            PERMA_STAKER2_NAME
        );
        bytecode = abi.encodePacked(vm.getCode("PermaStaker.sol:PermaStaker"), constructorArgs);
        permaStaker2 = deployContract(DeployType.CREATE3, salt, bytecode, "PermaStaker - Yearn");
        return (permaStaker1, permaStaker2);
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
