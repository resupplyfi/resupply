import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { Protocol } from "script/protocol/ProtocolConstants.sol";
import { ICore } from "src/interfaces/ICore.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IInsurancePool } from "src/interfaces/IInsurancePool.sol";
import { DeploymentConfig, CreateX } from "script/deploy/dependencies/DeploymentConfig.sol";
import { TenderlyHelper } from "script/utils/TenderlyHelper.sol";
import { CreateXHelper } from "script/utils/CreateXHelper.sol";

contract LaunchSetup is TenderlyHelper, CreateXHelper, BaseAction {
    address public constant deployer = Protocol.DEPLOYER;

    function run() public isBatch(deployer) {
        deployMode = DeployMode.FORK;
        maxGasPerBatch = 15_000_000;

        // Deploy updated contracts
        address newVoter = deployVoter();
        address newUtils = deployUtilities();

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

        executeBatch(true);
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
        return computeCreate3AddressFromSaltPreimage(salt, deployer, true, false);
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
        return computeCreate3AddressFromSaltPreimage(salt, deployer, true, false);
    }
}