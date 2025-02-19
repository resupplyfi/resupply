import "src/Constants.sol" as Constants;
import { console } from "forge-std/console.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";   
import { IFeeDepositController } from "src/interfaces/IFeeDepositController.sol";
import { Script } from "forge-std/Script.sol";

contract DistributeFees is Script {
    address pair1 = 0x748fC91A1AEcefe1d807B3eB86c51762E4C367A6;
    address pair2 = 0x748fC91A1AEcefe1d807B3eB86c51762E4C367A6;
    address dev = 0xFE11a5009f2121622271e7dd0FD470264e076af6;
    address feeDepositController = 0x4AA05D9eDb6d838E0f7fDA523B2Da29b1f337e1D;

    function run() public {
        vm.startBroadcast(dev);
        distributeFees();
        vm.stopBroadcast();
    }

    function distributeFees() public {
        // distribute fees
        IFeeDepositController(feeDepositController).distribute();
        IResupplyPair(pair1).withdrawFees();
        IResupplyPair(pair2).withdrawFees();
    }
}