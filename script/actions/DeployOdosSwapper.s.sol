import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { Protocol } from "script/protocol/ProtocolConstants.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { SafeHelper } from "script/utils/SafeHelper.sol";
import { CreateXHelper } from "script/utils/CreateXHelper.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { console } from "forge-std/console.sol";
import { ICore } from "src/interfaces/ICore.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ResupplyPairDeployer } from "src/protocol/ResupplyPairDeployer.sol";
import { ResupplyPair } from "src/protocol/ResupplyPair.sol";

contract LaunchSetup3 is SafeHelper, CreateXHelper, BaseAction {
    address public constant deployer = Protocol.DEPLOYER;
    IResupplyRegistry public constant registry = IResupplyRegistry(Protocol.REGISTRY);
    ResupplyPairDeployer public constant pairDeployer = ResupplyPairDeployer(Protocol.PAIR_DEPLOYER);
    
    function run() public isBatch(deployer) {
        deployMode = DeployMode.FORK;

        address predictedAddress = deployOdosSwapper();
        configureOdosSwapper(predictedAddress);
        updatePairImplementation();
        if (deployMode == DeployMode.PRODUCTION) executeBatch(true);
    }

    function deployOdosSwapper() public returns (address) {
        bytes32 salt = buildGuardedSalt(deployer, true, false, uint88(uint256(keccak256(bytes("SwapperOdos")))));
        bytes memory bytecode = abi.encodePacked(
            vm.getCode("SwapperOdos.sol:SwapperOdos"),
            abi.encode(
                address(core)
            )
        );
        address predictedAddress = computeCreate3AddressFromSaltPreimage(salt, deployer, true, false);
        if (addressHasCode(predictedAddress)) revert("Swapper already deployed");
        addToBatch(
            address(createXFactory),
            encodeCREATE3Deployment(
                salt, 
                bytecode
            )
        );
        console.log("Swapper deployed at", predictedAddress);
        return predictedAddress;
    }

    function configureOdosSwapper(address _odosSwapper) public {
        // Add as a default swapper
        address[] memory swappers = new address[](2);
        swappers[0] = registry.defaultSwappers(0);
        swappers[1] = _odosSwapper;
        _executeCore(address(registry), abi.encodeWithSelector(registry.setDefaultSwappers.selector, swappers));
        console.log("Swapper added to registry as default swapper");

        // Update all existing pairs to add the Odos swapper
        address[] memory pairs = registry.getAllPairAddresses();
        for (uint i = 0; i < pairs.length; i++) {
            IResupplyPair pair = IResupplyPair(pairs[i]);
            require(!pair.swappers(_odosSwapper), "Already set");
            _executeCore(address(pair), abi.encodeWithSelector(IResupplyPair.setSwapper.selector, _odosSwapper, true));
            require(pair.swappers(_odosSwapper), "Failed to set");
            console.log("Swapper added to: ", pair.name());
        }
    }

    function updatePairImplementation() public{
        _executeCore(Protocol.PAIR_DEPLOYER, abi.encodeWithSelector(ResupplyPairDeployer.setCreationCode.selector, type(ResupplyPair).creationCode));
        console.log("Pair implementation updated");
    }
}
