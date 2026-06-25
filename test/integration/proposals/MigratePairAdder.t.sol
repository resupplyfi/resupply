// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol } from "src/Constants.sol";
import { PairAdder } from "src/dao/operators/PairAdder.sol";
import { ICore } from "src/interfaces/ICore.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { PermissionHelper } from "script/utils/PermissionHelper.sol";
import { MigratePairAdder } from "script/proposals/MigratePairAdder.s.sol";
import { BaseProposalTest } from "test/integration/proposals/BaseProposalTest.sol";

contract MigratePairAdderTest is BaseProposalTest {
    MigratePairAdder public script;
    address public pairAdderV2;

    function setUp() public override {
        super.setUp();

        pairAdderV2 = address(new PairAdder(Protocol.CORE, Protocol.REGISTRY));
        vm.setEnv("PAIR_ADDER_V2", vm.toString(pairAdderV2));

        script = new MigratePairAdder();
        IVoter.Action[] memory actions = script.buildProposalCalldata();
        uint256 proposalId = createProposal(actions);
        simulatePassingVote(proposalId);
        executeProposal(proposalId);
    }

    function test_RegistryPairAdderUpdated() public {
        assertEq(registry.getAddress("PAIR_ADDER"), pairAdderV2, "registry not updated");
        assertGt(pairAdderV2.code.length, 0, "pair adder v2 missing code");
    }

    function test_PermissionsMigrated() public {
        assertTrue(PermissionHelper.isEnabled(pairAdderV2, Protocol.REGISTRY, IResupplyRegistry.addPair.selector), "new pair adder permission missing");
        assertFalse(PermissionHelper.isEnabled(script.oldPairAdder(), Protocol.REGISTRY, IResupplyRegistry.addPair.selector), "old pair adder permission still enabled");
    }

    function test_ProposalPayload() public {
        IVoter.Action[] memory actions = script.buildProposalCalldata();
        assertEq(actions.length, 3, "unexpected action count");

        assertEq(actions[0].target, Protocol.REGISTRY, "action 0 target");
        assertEq(keccak256(actions[0].data), keccak256(abi.encodeWithSelector(IResupplyRegistry.setAddress.selector, "PAIR_ADDER", pairAdderV2)), "action 0 data");

        assertEq(actions[1].target, Protocol.CORE, "action 1 target");
        assertEq(keccak256(actions[1].data), keccak256(abi.encodeWithSelector(ICore.setOperatorPermissions.selector, pairAdderV2, Protocol.REGISTRY, IResupplyRegistry.addPair.selector, true, address(0))), "action 1 data");

        assertEq(actions[2].target, Protocol.CORE, "action 2 target");
        assertEq(keccak256(actions[2].data), keccak256(abi.encodeWithSelector(ICore.setOperatorPermissions.selector, script.oldPairAdder(), Protocol.REGISTRY, IResupplyRegistry.addPair.selector, false, address(0))), "action 2 data");
    }
}
