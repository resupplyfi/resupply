import { Utilities } from "src/protocol/Utilities.sol";
import { BaseDeploy } from "script/deploy/dependencies/BaseDeploy.s.sol";
import { console } from "forge-std/console.sol";

contract DeployUtilities is BaseDeploy {
    function run() public {
        // ============================================
        // ====== Utilities ================
        // ============================================
        deployMode = DeployMode.TENDERLY;
        bytes memory constructorArgs;
        bytes memory bytecode;
        address predictedAddress;
        constructorArgs = abi.encode(
            address(registry)
        );
        bytecode = abi.encodePacked(vm.getCode("Utilities.sol:Utilities"), constructorArgs);
        salt = buildGuardedSalt(
            dev, 
            true,   // enablePermissionedDeploy
            false,  // enableCrossChain Protection
            uint88(uint256(keccak256(bytes("Utilities"))))
        );
        predictedAddress = computeCreate3AddressFromSaltPreimage(salt, dev, true, false);
        if (!addressHasCode(predictedAddress)) {
            addToBatch(
                address(createXFactory),
                encodeCREATE3Deployment(salt, bytecode)
            );
        }
        utilities = Utilities(predictedAddress);
        console.log("Utilities deployed at", address(utilities));
        writeAddressToJson("UTILITIES", predictedAddress);
    }
}