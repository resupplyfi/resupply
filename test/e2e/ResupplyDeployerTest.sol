// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "./BasePairTest.t.sol";
import "src/interfaces/IResupplyPair.sol";
import "src/protocol/ResupplyPairDeployer.sol";

contract ResupplyDeployerTest is BasePairTest {
    function setUp() public {
        string memory _envKey = vm.envString("MAINNET_URL");
        vm.createSelectFork(_envKey, 16_474_174);
    }

    function testDeployPair() public {
        defaultSetUp();
        deployDefaultLendingPairs();
        uint256 length = registry.registeredPairsLength();
        for(uint256 i = 0; i < length; i++){
            ResupplyPair pair = ResupplyPair(registry.registeredPairs(i));
            console.log("======================================");
            console.log("    Deployed Pair     ");
            console.log("======================================");
            console.log("pair: ", address(pair));
            console.log("pair: ", pair.name());
            console.log("collateral: ", address(pair.collateral()));
            console.log("underlying: ", address(pair.underlying()));
        }
        
    }
}
