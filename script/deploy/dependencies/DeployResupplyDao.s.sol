import "src/Constants.sol" as Constants;
import { CreateX } from "src/Constants.sol";
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
    function deployDaoContracts() public {
        core = deployCore();
        govToken = deployGovToken();
        vestManager = deployVestManager();
        stablecoin = Stablecoin(deployStablecoin());
        registry = IResupplyRegistry(deployRegistry());
        staker = deployGovStaker();
        autoStakeCallback = deployAutoStakeCallback();
        voter = deployVoter();
        emissionsController = deployEmissionsController();
        treasury = deployTreasury();
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
        address lzEndpoint = Constants.Mainnet.LAYERZERO_ENDPOINTV2;
        if (block.chainid == Constants.Sepolia.CHAIN_ID) lzEndpoint = Constants.Sepolia.LAYERZERO_ENDPOINTV2;
        bytes memory constructorArgs = abi.encode(address(core), lzEndpoint);
        bytes32 salt = CreateX.SALT_STABLECOIN;
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
        bytes32 salt = CreateX.SALT_REGISTRY;
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
        bytes32 salt = CreateX.SALT_CORE;
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
        bytes32 vmSalt = CreateX.SALT_VEST_MANAGER;
        address _vestManagerAddress = computeCreate3AddressFromSaltPreimage(vmSalt, dev, true, false);
        bytes32 salt = CreateX.SALT_GOV_TOKEN;
        address predictedAddress = computeCreate3AddressFromSaltPreimage(salt, dev, true, false);
        address lzEndpoint = Constants.Mainnet.LAYERZERO_ENDPOINTV2;
        if (block.chainid == Constants.Sepolia.CHAIN_ID) lzEndpoint = Constants.Sepolia.LAYERZERO_ENDPOINTV2;
        if (addressHasCode(predictedAddress)) return predictedAddress;
        bytes memory constructorArgs = abi.encode(
            address(core),
            _vestManagerAddress,
            GOV_TOKEN_INITIAL_SUPPLY,
            lzEndpoint,
            GOV_TOKEN_NAME, 
            GOV_TOKEN_SYMBOL
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
        bytes32 salt = CreateX.SALT_VEST_MANAGER;
        address predictedAddress = computeCreate3AddressFromSaltPreimage(salt, dev, true, false);
        if (addressHasCode(predictedAddress)) return predictedAddress;
        bytes memory constructorArgs = abi.encode(
            address(core),
            address(govToken), 
            address(PRISMA_TOKENS_BURN_ADDRESS), 
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
        bytes32 salt = CreateX.SALT_GOV_STAKER;
        address predictedAddress = computeCreate3AddressFromSaltPreimage(salt, dev, true, false);
        if (addressHasCode(predictedAddress)) return predictedAddress;
        bytes memory constructorArgs = abi.encode(
            address(core),
            address(registry),
            address(govToken), 
            STAKER_COOLDOWN_EPOCHS
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
        bytes32 salt = CreateX.SALT_VOTER;
        address predictedAddress = computeCreate3AddressFromSaltPreimage(salt, dev, true, false);
        if (addressHasCode(predictedAddress)) return predictedAddress;
        bytes memory constructorArgs = abi.encode(
            address(core), 
            IGovStaker(address(staker)), 
            VOTER_MIN_CREATE_PROPOSAL_PCT, 
            VOTER_QUORUM_PCT
        );
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
        bytes32 salt = CreateX.SALT_EMISSIONS_CONTROLLER;
        address predictedAddress = computeCreate3AddressFromSaltPreimage(salt, dev, true, false);
        if (addressHasCode(predictedAddress)) return predictedAddress;
        bytes memory constructorArgs = abi.encode(
            address(core), 
            address(govToken), 
            getEmissionsSchedule(), 
            EMISSIONS_CONTROLLER_EPOCHS_PER,        // epochs per
            EMISSIONS_CONTROLLER_TAIL_RATE,         // tail rate 2%
            EMISSIONS_CONTROLLER_BOOTSTRAP_EPOCHS   // Bootstrap epochs
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
        bytes32 salt = CreateX.SALT_TREASURY;
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
        bytes32 salt = CreateX.SALT_PERMA_STAKER_CONVEX;
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
        salt = CreateX.SALT_PERMA_STAKER_YEARN;
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
        schedule[0] = 4 * 10 ** 16;     // 2%
        schedule[1] = 6 * 10 ** 16;     // 4%
        schedule[2] = 8 * 10 ** 16;     // 6%
        schedule[3] = 10 * 10 ** 16;     // 8%
        schedule[4] = 12 * 10 ** 16;    // 10%
        return schedule;
    }
}
