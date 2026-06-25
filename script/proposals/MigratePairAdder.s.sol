// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol } from "src/Constants.sol";
import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { console } from "lib/forge-std/src/console.sol";
import { BaseProposal } from "script/proposals/BaseProposal.sol";
import { PermissionHelper } from "script/utils/PermissionHelper.sol";

contract MigratePairAdder is BaseAction, BaseProposal {
    string public constant PAIR_ADDER_KEY = "PAIR_ADDER";
    address public immutable pairAdderV2;

    constructor() {
        pairAdderV2 = vm.envAddress("PAIR_ADDER_V2");
        require(pairAdderV2 != address(0), "PAIR_ADDER_V2 not set");
    }

    function run() public isBatch(deployer) {
        IVoter.Action[] memory actions = buildProposalCalldata();

        proposeVote(actions, "Migrate PairAdder to fixed implementation");
        uint256 proposalId = voter.getProposalCount() - 1;

        for (uint256 i = 0; i < actions.length; i++) {
            (address target_, bytes memory data_) = voter.proposalPayload(proposalId, i);
            console.log("Action", i + 1);
            console.log(target_);
            console.logBytes(data_);
            console.log("--------------------------------");
        }

        deployMode = DeployMode.PRODUCTION;
        if (deployMode == DeployMode.PRODUCTION) executeBatch(true);
    }

    function buildProposalCalldata() public view override returns (IVoter.Action[] memory actions) {
        actions = new IVoter.Action[](3);

        actions[0] = IVoter.Action({ target: Protocol.REGISTRY, data: abi.encodeWithSelector(IResupplyRegistry.setAddress.selector, PAIR_ADDER_KEY, pairAdderV2) });

        actions[1] = PermissionHelper.buildOperatorPermissionAction(pairAdderV2, Protocol.REGISTRY, IResupplyRegistry.addPair.selector, true);

        actions[2] = PermissionHelper.buildOperatorPermissionAction(Protocol.PAIR_ADDER_OLD, Protocol.REGISTRY, IResupplyRegistry.addPair.selector, false);
    }
}
