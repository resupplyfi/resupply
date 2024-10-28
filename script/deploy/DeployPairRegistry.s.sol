// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import { BaseScript } from "frax-std/BaseScript.sol";
import { console } from "frax-std/FraxTest.sol";
import "src/Constants.sol" as Constants;
import { RelendPairRegistry } from "src/protocol/RelendPairRegistry.sol";
import { DeployScriptReturn } from "./DeployScriptReturn.sol";

function deployPairRegistry() returns (DeployScriptReturn memory _return) {

    RelendPairRegistry _fraxlendPairRegistry = new RelendPairRegistry(
        address(Constants.Mainnet.STABLE_TOKEN),
        address(Constants.Mainnet.CORE)
    );
    _return.address_ = address(_fraxlendPairRegistry);
    _return.constructorParams = "";
    _return.contractName = "RelendPairRegistry";
    // _fraxlendPairRegistry.setDeployers(_deployers, true);
}

contract DeployPairRegistry is BaseScript {
    function run() external broadcaster returns (DeployScriptReturn memory _return) {
        _return = deployPairRegistry();
    }
}
