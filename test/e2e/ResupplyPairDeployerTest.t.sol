// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "./BasePairTest.t.sol";
import "src/interfaces/IFraxlendPair.sol";
import "src/protocol/ResupplyPairDeployer.sol";

contract ResupplyDeployerTest is BasePairTest {
    function setUp() public {
        string memory _envKey = vm.envString("MAINNET_URL");
        vm.createSelectFork(_envKey, 16_474_174);
    }

    function testDeployPair() public {
        defaultSetUp();
        FraxlendPair pair = deployDefaultLendingPair();
        console.log("======================================");
        console.log("    Deployed Pair     ");
        console.log("======================================");
        console.log("pair: ", address(pair));
        console.log("collateral: ", address(pair.collateralContract()));
        console.log("underlying: ", address(pair.underlyingAsset()));
    }
}
