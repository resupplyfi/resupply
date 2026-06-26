// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Mainnet } from "src/Constants.sol";
import { PairAdder } from "src/dao/operators/PairAdder.sol";
import { IAuthHook } from "src/interfaces/IAuthHook.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { Setup } from "test/e2e/Setup.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract PairAdderTest is Setup {
    PairAdder public pairAdder;

    function setUp() public override {
        super.setUp();

        pairAdder = new PairAdder(address(core), address(registry));

        vm.startPrank(address(core));
        registry.setAddress("PAIR_DEPLOYER", address(deployer));
        core.setOperatorPermissions(address(pairAdder), address(registry), IResupplyRegistry.addPair.selector, true, IAuthHook(address(0)));
        vm.stopPrank();
    }

    function test_AddPairCallsRegistry() public {
        uint256 lengthBefore = registry.registeredPairsLength();
        IResupplyPair newPair = deployLendingPairWithDefaultConfigAs(address(core), 0, Mainnet.CURVELEND_YNETH_CRVUSD, Mainnet.CURVELEND_YNETH_CRVUSD_ID);
        string memory name = IERC20Metadata(address(newPair)).name();

        assertGt(address(newPair).code.length, 0, "pair not deployed");
        assertEq(registry.registeredPairsLength(), lengthBefore, "pair should not start registered");
        assertEq(registry.pairsByName(name), address(0), "name should not start registered");

        vm.prank(address(core));
        pairAdder.addPair(address(newPair));

        assertEq(registry.registeredPairsLength(), lengthBefore + 1, "pair not added");
        assertEq(registry.registeredPairs(lengthBefore), address(newPair), "registered pair mismatch");
        assertEq(registry.pairsByName(name), address(newPair), "name mapping not updated");
    }

    function test_AddPairRejectsUntrustedPair() public {
        vm.expectRevert("Pair not deployed by trusted deployer");
        vm.prank(address(core));
        pairAdder.addPair(address(0xBEEF));
    }
}
