import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { Protocol } from "script/protocol/ProtocolConstants.sol";
import { Guardian } from "src/dao/operators/Guardian.sol";
import { ITreasuryManager } from "src/interfaces/ITreasuryManager.sol";
import { ITreasury } from "src/interfaces/ITreasury.sol";
import { TenderlyHelper } from "script/utils/TenderlyHelper.sol";
import { CreateXHelper } from "script/utils/CreateXHelper.sol";
import { CreateX } from "script/deploy/dependencies/DeploymentConfig.sol";

contract LaunchSetup3 is TenderlyHelper, CreateXHelper, BaseAction {
    address public constant deployer = Protocol.DEPLOYER;
    address public guardian;
    address public treasuryManager;
    address public rsup = 0x419905009e4656fdC02418C7Df35B1E61Ed5F726;
    
    function run() public isBatch(deployer) {
        deployMode = DeployMode.FORK;
        address grantRecipient = 0x0000000000000000000000000000000000000000;
        uint256 grantAmount = 1_000e18;
        transferGrant(grantRecipient, grantAmount);
        deployGuardianAndConfigure();
        deployTreasuryManagerAndConfigure();
        
        if (deployMode == DeployMode.PRODUCTION) executeBatch(true);
    }

    function transferGrant(address _recipient, uint256 _amount) public {
        _executeCore(
            Protocol.TREASURY,
            abi.encodeWithSelector(
                ITreasury.retrieveTokenExact.selector, 
                rsup,
                _recipient,
                _amount
            )
        );
    }

    function deployGuardianAndConfigure() public {
        // 1 Deploy Guardian
        // 2 Set permissions
        // 3 Set guardian role
        bytes32 salt = CreateX.SALT_GUARDIAN;
        bytes memory constructorArgs = abi.encode(
            Protocol.CORE,
            Protocol.TREASURY
        );
        bytes memory bytecode = vm.getCode("Guardian.sol:Guardian");
        addToBatch(
            address(createXFactory),
            encodeCREATE3Deployment(salt, bytecode)
        );
        guardian = computeCreate3AddressFromSaltPreimage(salt, deployer, true, false);
        require(guardian.code.length > 0, "deployment failed");
        // Set guardian
        _executeCore(
            guardian,
            abi.encodeWithSelector(
                IGuardian.setGuardian.selector,
                deployer
            )
        );
    }

    function deployTreasuryManagerAndConfigure() public {
        // 1 Deploy TreasuryManager
        // 2 Set permissions
        // 3 Set treasury manager role
        bytes32 salt = CreateX.SALT_TREASURY_MANAGER;
        bytes memory constructorArgs = abi.encode(
            Protocol.CORE,
            Protocol.TREASURY
        );
        bytes memory bytecode = abi.encodePacked(vm.getCode("TreasuryManager.sol:TreasuryManager"), constructorArgs);
        addToBatch(
            address(createXFactory),
            encodeCREATE3Deployment(salt, bytecode)
        );
        address treasuryManager = computeCreate3AddressFromSaltPreimage(salt, deployer, true, false);
        require(treasuryManager.code.length > 0, "deployment failed");
        // Set manager
        _executeCore(
            treasuryManager,
            abi.encodeWithSelector(
                ITreasuryManager.setManager.selector,
                deployer
            )
        );
        setTreasuryManagerPermissions(deployer, false); // revoke deployer permissions
        setTreasuryManagerPermissions(treasuryManager, true); // grant permissions to treasury manager operator
    }

    function setTreasuryManagerPermissions(address _caller, bool _approve) internal {
        setCorePermissions(
            ITreasury.retrieveToken.selector,
            _caller,
            Protocol.TREASURY,
            _approve,
            address(0)
        );
        setCorePermissions(
            ITreasury.retrieveETH.selector,
            _caller,
            Protocol.TREASURY,
            _approve,
            address(0)
        );
        setCorePermissions(
            ITreasury.retrieveTokenExact.selector,
            _caller,
            Protocol.TREASURY,
            _approve,
            address(0)
        );
        setCorePermissions(
            ITreasury.retrieveETHExact.selector,
            _caller,
            Protocol.TREASURY,
            _approve,
            address(0)
        );
        setCorePermissions(
            ITreasury.safeExecute.selector,
            _caller,
            Protocol.TREASURY,
            _approve,
            address(0)
        );
        setCorePermissions(
            ITreasury.execute.selector,
            _caller,
            Protocol.TREASURY,
            _approve,
            address(0)
        );
        setCorePermissions(
            ITreasury.setTokenApproval.selector,
            _caller,
            Protocol.TREASURY,
            _approve,
            address(0)
        );
    }

    function setGuardianPermissions(address _caller, bool _approve) internal {
        setCorePermissions(
            IGuardian.setGuardian.selector,
            _caller,
            guardian,
        )
    }
}