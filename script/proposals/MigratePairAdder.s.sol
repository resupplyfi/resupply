// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol } from "src/Constants.sol";
import { Script } from "lib/forge-std/src/Script.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { IPairAdder } from "src/interfaces/IPairAdder.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { console } from "lib/forge-std/src/console.sol";
import { PermissionHelper } from "script/utils/PermissionHelper.sol";

contract MigratePairAdder is Script {
    IResupplyRegistry public constant registry = IResupplyRegistry(Protocol.REGISTRY);
    IVoter public constant voter = IVoter(Protocol.VOTER);

    string public constant DESCRIPTION = "Migrate PairAdder to fixed implementation";
    string public constant PAIR_ADDER_KEY = "PAIR_ADDER";
    address public constant PAIR_ADDER = 0x6Ba4D235B71Cb868bC4576E15dD75701DE6D6929;
    address public immutable previousPairAdder;

    constructor() {
        require(PAIR_ADDER.code.length > 0, "PAIR_ADDER not deployed");
        require(IPairAdder(PAIR_ADDER).core() == Protocol.CORE, "wrong PAIR_ADDER core");
        require(IPairAdder(PAIR_ADDER).registry() == Protocol.REGISTRY, "wrong PAIR_ADDER registry");
        previousPairAdder = registry.getAddress(PAIR_ADDER_KEY);
        require(previousPairAdder != address(0), "PAIR_ADDER not set");
        require(previousPairAdder != PAIR_ADDER, "PAIR_ADDER already migrated");
    }

    function run() public {
        IVoter.Action[] memory actions = buildProposalCalldata();
        printCallData(actions);

        vm.startBroadcast();
        (, address proposer,) = vm.readCallers();
        uint256 proposalId = voter.createNewProposal(proposer, actions, DESCRIPTION);
        vm.stopBroadcast();

        console.log("Proposal created by:", proposer);
        console.log("Proposal ID:", proposalId);
    }

    function buildProposalCalldata() public view returns (IVoter.Action[] memory actions) {
        actions = new IVoter.Action[](3);

        actions[0] = IVoter.Action({ target: Protocol.REGISTRY, data: abi.encodeWithSelector(IResupplyRegistry.setAddress.selector, PAIR_ADDER_KEY, PAIR_ADDER) });

        actions[1] = PermissionHelper.buildOperatorPermissionAction(PAIR_ADDER, Protocol.REGISTRY, IResupplyRegistry.addPair.selector, true);

        actions[2] = PermissionHelper.buildOperatorPermissionAction(previousPairAdder, Protocol.REGISTRY, IResupplyRegistry.addPair.selector, false);
    }

    function printCallData(IVoter.Action[] memory actions) public view {
        for (uint256 i = 0; i < actions.length; i++) {
            console.log("Action", i + 1);
            console.log(actions[i].target);
            console.logBytes(actions[i].data);
            console.log("--------------------------------");
        }
    }
}
