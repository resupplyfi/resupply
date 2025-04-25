pragma solidity 0.8.28;

import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { Protocol, Prisma } from "src/Constants.sol";
import { Guardian } from "src/dao/operators/Guardian.sol";
import { ITreasuryManager } from "src/interfaces/ITreasuryManager.sol";
import { ITreasury } from "src/interfaces/ITreasury.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { IGuardian } from "src/interfaces/IGuardian.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { TenderlyHelper } from "script/utils/TenderlyHelper.sol";
import { CreateXHelper } from "script/utils/CreateXHelper.sol";
import { CreateX } from "src/Constants.sol";
import { IPrismaCore } from "src/interfaces/IPrismaCore.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { ReusdOracle } from "src/protocol/ReusdOracle.sol";
import { console } from "lib/forge-std/src/console.sol";
import { ISimpleReceiver } from "src/interfaces/ISimpleReceiver.sol";
import { ITreasuryManager } from "src/interfaces/ITreasuryManager.sol";
import { ICore } from "src/interfaces/ICore.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPrismaVoterProxy } from "src/interfaces/prisma/IPrismaVoterProxy.sol";

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