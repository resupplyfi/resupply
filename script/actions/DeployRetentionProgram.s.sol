pragma solidity 0.8.30;

import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { Protocol } from "src/Constants.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { SafeHelper } from "script/utils/SafeHelper.sol";
import { CreateXHelper } from "script/utils/CreateXHelper.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { console } from "forge-std/console.sol";
import { RetentionIncentives } from "src/dao/RetentionIncentives.sol";
import { RetentionProgramJsonParser } from "test/utils/RetentionProgramJsonParser.sol";

contract LaunchSetup3 is SafeHelper, CreateXHelper, BaseAction {
    string public constant RETENTION_JSON_FILE_PATH = "deployment/data/ip_retention_snapshot.json";

    address public constant deployer = Protocol.DEPLOYER;
    IResupplyRegistry public constant registry = IResupplyRegistry(Protocol.REGISTRY);
    
    address[] public retentionUsers;
    uint256[] public retentionAmounts;

    uint256 public constant TREASURY_WEEKLY_ALLOCATION = 34_255e18;
    uint256 public constant FINAL_SUPPLY = 38297485116207462898268702;

    function run() public isBatch(deployer) {
        deployMode = DeployMode.FORK;

        _loadRetentionData(false); // true to print values to console

        address retention = deployRetentionProgram();

        RetentionIncentives incentives = RetentionIncentives(retention);
        //set user balances
        addToBatch(
            address(incentives), 
            abi.encodeWithSelector(incentives.setAddressBalances.selector, 
                retentionUsers, 
                retentionAmounts
            )
        );
        require(incentives.isFinalized(), "incentives not finalized");
        require(incentives.totalSupply() == FINAL_SUPPLY, "incentives total supply not correct");

        deployReceiver(retention);
        if (deployMode == DeployMode.PRODUCTION) executeBatch(true);
    }

    function deployRetentionProgram() public returns (address) {
        bytes32 salt = buildGuardedSalt(deployer, true, false, uint88(uint256(keccak256(bytes("RetentionIncentives")))));
        bytes memory bytecode = abi.encodePacked(
            vm.getCode("RetentionIncentives.sol:RetentionIncentives"),
            abi.encode(
                address(core),
                address(registry),
                address(Protocol.GOV_TOKEN),
                address(Protocol.INSURANCE_POOL)
            )
        );
        address predictedAddress = computeCreate3AddressFromSaltPreimage(salt, deployer, true, false);
        if (addressHasCode(predictedAddress)) revert("already deployed");
        addToBatch(
            address(createXFactory),
            encodeCREATE3Deployment(
                salt, 
                bytecode
            )
        );
        console.log("rentention deployed at", predictedAddress);
        return predictedAddress;
    }

    function deployReceiver(address _retention) public returns (address) {
        bytes32 salt = buildGuardedSalt(deployer, true, false, uint88(uint256(keccak256(bytes("RetentionReceiver")))));
        bytes memory bytecode = abi.encodePacked(
            vm.getCode("RetentionReceiver.sol:RetentionReceiver"),
            abi.encode(
                address(core),
                address(registry),
                address(Protocol.EMISSIONS_CONTROLLER),
                address(_retention),
                TREASURY_WEEKLY_ALLOCATION
            )
        );
        address predictedAddress = computeCreate3AddressFromSaltPreimage(salt, deployer, true, false);
        if (addressHasCode(predictedAddress)) revert("already deployed");
        addToBatch(
            address(createXFactory),
            encodeCREATE3Deployment(
                salt, 
                bytecode
            )
        );
        console.log("retention receiver deployed at", predictedAddress);
        return predictedAddress;
    }

    function _loadRetentionData(bool print) internal {
        RetentionProgramJsonParser.RetentionData memory data = 
            RetentionProgramJsonParser.parseRetentionSnapshot(vm.readFile(RETENTION_JSON_FILE_PATH));
        retentionUsers = data.users;
        retentionAmounts = data.amounts;
        if(print) {
            for (uint256 i = 0; i < retentionUsers.length; i++) {
                console.log(i, retentionUsers[i], retentionAmounts[i]);
            }
        }
    }
}
