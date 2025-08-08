pragma solidity 0.8.30;

import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { Protocol, Prisma } from "src/Constants.sol";
import { ITreasury } from "src/interfaces/ITreasury.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { TenderlyHelper } from "script/utils/TenderlyHelper.sol";
import { CreateXHelper } from "script/utils/CreateXHelper.sol";
import { CreateX } from "src/Constants.sol";
import { ReusdOracle } from "src/protocol/ReusdOracle.sol";
import { console } from "lib/forge-std/src/console.sol";

contract DeployOracle is TenderlyHelper, CreateXHelper, BaseAction {
    address public constant deployer = Protocol.DEPLOYER;
    
    function run() public isBatch(deployer) {
        deployMode = DeployMode.FORK;

        deployOracle();
       
        if (deployMode == DeployMode.PRODUCTION) executeBatch(true);
    }

    function deployOracle() public {
        // 1 Deploy oracle
        // 2 Set on registry
        bytes32 salt = CreateX.SALT_REUSD_ORACLE;
        bytes memory constructorArgs = abi.encode(
            "reUSD oracle"
        );
        bytes memory bytecode = abi.encodePacked(vm.getCode("ReusdOracle.sol:ReusdOracle"), constructorArgs);
        addToBatch(
            address(createXFactory),
            encodeCREATE3Deployment(salt, bytecode)
        );
        address oracle = computeCreate3AddressFromSaltPreimage(salt, deployer, true, false);
        console.log("oracle at", oracle);
        require(oracle.code.length > 0, "deployment failed");
        
        ReusdOracle oraclecontract = ReusdOracle(oracle);
        uint256 price = ReusdOracle(oracle).price();
        console.log("reusd usd: ", oraclecontract.price());
        console.log("reusd crvusd: ", oraclecontract.priceAsCrvusd());
        console.log("reusd frxusd: ", oraclecontract.priceAsFrxusd());

        
        // Set address in registry
        _executeCore(
            address(Protocol.REGISTRY),
            abi.encodeWithSelector(
                IResupplyRegistry.setAddress.selector,
                "REUSD_ORACLE",
                oracle
            )
        );

        console.log("REUSD_ORACLE key: ", IResupplyRegistry(Protocol.REGISTRY).getAddress("REUSD_ORACLE"));
    }
}