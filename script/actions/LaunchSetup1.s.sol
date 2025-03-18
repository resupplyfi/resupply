import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { Protocol } from "script/protocol/ProtocolConstants.sol";
import { ICore } from "src/interfaces/ICore.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IInsurancePool } from "src/interfaces/IInsurancePool.sol";
import { DeploymentConfig, CreateX } from "script/deploy/dependencies/DeploymentConfig.sol";
import { TenderlyHelper } from "script/utils/TenderlyHelper.sol";
import { CreateXHelper } from "script/utils/CreateXHelper.sol";
import { ITreasury } from "src/interfaces/ITreasury.sol";
import { console } from "forge-std/console.sol";

contract LaunchSetup is TenderlyHelper, CreateXHelper, BaseAction {
    address public constant deployer = Protocol.DEPLOYER;
    address public newVoter;
    address public newUtils;
    address public newTreasury;
    address public newFeeDepositController;

    function run() public isBatch(deployer) {
        deployMode = DeployMode.PRODUCTION;
        maxGasPerBatch = 15_000_000;
        uint256 customNonce = 13;

        // Deploy updated contracts
        newVoter = deployVoter();
        newUtils = deployUtilities();
        newTreasury = deployTreasury();
        newFeeDepositController = deployFeeDepositController();
        updateRegistry();
        setOperatorPermissions();
        returnTokens();

        console.log("newVoter: %s", newVoter);
        console.log("newUtils: %s", newUtils);
        console.log("newTreasury: %s", newTreasury);
        console.log("newFeeDepositController: %s", newFeeDepositController);

        if (deployMode == DeployMode.PRODUCTION) executeBatch(true, customNonce);
    }

    function updateRegistry() internal {
        // Set Voter address in registry
        _executeCore(
            address(Protocol.REGISTRY),
            abi.encodeWithSelector(
                IResupplyRegistry.setAddress.selector,
                "VOTER",
                newVoter
            )
        );

        // Set Utilities address in registry
        _executeCore(
            address(Protocol.REGISTRY),
            abi.encodeWithSelector(
                IResupplyRegistry.setAddress.selector,
                "UTILITIES",
                newUtils
            )
        );

        // Set Treasury address in registry
        _executeCore(
            address(Protocol.REGISTRY),
            abi.encodeWithSelector(
                IResupplyRegistry.setTreasury.selector,
                newTreasury
            )
        );

        // Set FeeDepositController address in registry
        _executeCore(
            address(Protocol.REGISTRY),
            abi.encodeWithSelector(IResupplyRegistry.setAddress.selector, "FEE_DEPOSIT_CONTROLLER", newFeeDepositController)
        );
    }

    function setOperatorPermissions() internal {
        // Grant multisig proposal cancellation permissions on Voter
        _executeCore(
            address(Protocol.CORE),
            abi.encodeWithSelector(
                ICore.setOperatorPermissions.selector,
                deployer,
                Protocol.VOTER,
                IVoter.cancelProposal.selector,
                true,
                address(0)
            )
        );

        // Grant multisig setAddresspermissions on Registry
        _executeCore(
            address(Protocol.CORE),
            abi.encodeWithSelector(
                ICore.setOperatorPermissions.selector,
                deployer,
                Protocol.REGISTRY,
                IResupplyRegistry.setAddress.selector,
                true,
                address(0)
            )
        );

        _executeCore(
            address(Protocol.INSURANCE_POOL),
            abi.encodeWithSelector(
                IInsurancePool.setWithdrawTimers.selector,
                7 days, // _withdrawLength
                3 days  // _withdrawWindow
            )
        );
    }

    function deployVoter() public returns (address) {
        bytes32 salt = CreateX.SALT_VOTER;
        bytes memory constructorArgs = abi.encode(
            Protocol.CORE,
            Protocol.GOV_STAKER, 
            DeploymentConfig.VOTER_MIN_CREATE_PROPOSAL_PCT, 
            DeploymentConfig.VOTER_QUORUM_PCT
        );
        bytes memory bytecode = abi.encodePacked(vm.getCode("Voter.sol:Voter"), constructorArgs);
        addToBatch(
            address(createXFactory),
            encodeCREATE3Deployment(salt, bytecode)
        );
        address deployedAddress = computeCreate3AddressFromSaltPreimage(salt, deployer, true, false);
        require(deployedAddress.code.length > 0, "deployment failed");
        return deployedAddress;
    }

    function deployUtilities() public returns (address) {
        bytes memory constructorArgs = abi.encode(
            address(Protocol.REGISTRY)
        );
        bytes memory bytecode = abi.encodePacked(vm.getCode("Utilities.sol:Utilities"), constructorArgs);
        bytes32 salt = buildGuardedSalt(
            deployer, 
            true,   // enablePermissionedDeploy
            false,  // enableCrossChain Protection
            uint88(uint256(keccak256(bytes("Utilities2"))))
        );
        addToBatch(
            address(createXFactory),
            encodeCREATE3Deployment(salt, bytecode)
        );
        address deployedAddress = computeCreate3AddressFromSaltPreimage(salt, deployer, true, false);
        require(deployedAddress.code.length > 0, "deployment failed");
        return deployedAddress;
    }

    function deployTreasury() public returns (address) {
        bytes32 salt = CreateX.SALT_TREASURY;
        bytes memory constructorArgs = abi.encode(Protocol.CORE);
        bytes memory bytecode = abi.encodePacked(vm.getCode("Treasury.sol:Treasury"), constructorArgs);
        addToBatch(
            address(createXFactory),
            encodeCREATE3Deployment(salt, bytecode)
        );
        address deployedAddress = computeCreate3AddressFromSaltPreimage(salt, deployer, true, false);
        require(deployedAddress.code.length > 0, "deployment failed");
        return deployedAddress;
    }

    function deployFeeDepositController() public returns (address) {
        bytes memory constructorArgs = abi.encode(
            Protocol.CORE,
            Protocol.REGISTRY,
            DeploymentConfig.FEE_SPLIT_IP,
            DeploymentConfig.FEE_SPLIT_TREASURY
        );
        bytes memory bytecode = abi.encodePacked(vm.getCode("FeeDepositController.sol:FeeDepositController"), constructorArgs);
        bytes32 salt = buildGuardedSalt(
            deployer, 
            true,   // enablePermissionedDeploy
            false,  // enableCrossChain Protection
            uint88(uint256(keccak256(bytes("FeeDepositController2"))))
        );
        addToBatch(
            address(createXFactory),
            encodeCREATE3Deployment(salt, bytecode)
        );
        address deployedAddress = computeCreate3AddressFromSaltPreimage(salt, deployer, true, false);
        require(deployedAddress.code.length > 0, "deployment failed");
        return deployedAddress;
    }

    function returnTokens() public {
        address recipient = 0xAAc0aa431c237C2C0B5f041c8e59B3f1a43aC78F;
        address token = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        _executeCore(
            address(Protocol.TREASURY),
            abi.encodeWithSelector(ITreasury.retrieveToken.selector, token, recipient)
        );
    }
}