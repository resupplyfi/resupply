// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol } from "src/Constants.sol";
import { Script } from "lib/forge-std/src/Script.sol";
import { console } from "lib/forge-std/src/console.sol";
import { IEmissionsController } from "src/interfaces/IEmissionsController.sol";
import { IRetentionReceiver } from "src/interfaces/IRetentionReceiver.sol";
import { ITreasury } from "src/interfaces/ITreasury.sol";
import { IVoter } from "src/interfaces/IVoter.sol";

contract RerouteRetentionEmissions is Script {
    IEmissionsController public constant EMISSIONS_CONTROLLER = IEmissionsController(Protocol.EMISSIONS_CONTROLLER);
    IVoter public constant VOTER = IVoter(Protocol.VOTER);

    string public constant DESCRIPTION = "Conclude retention program and route its weekly emissions (6.25%) to borrowers";

    uint256 public constant EXPECTED_BORROWER_WEIGHT = 1875;
    uint256 public constant EXPECTED_RETENTION_WEIGHT = 625;
    uint256 public constant NEW_BORROWER_WEIGHT = 2500;
    uint256 public constant NEW_RETENTION_WEIGHT = 0;

    function run() public {
        IVoter.Action[] memory actions = buildProposalCalldata();
        printCallData(actions);

        vm.startBroadcast();
        (, address proposer,) = vm.readCallers();
        uint256 proposalId = VOTER.createNewProposal(proposer, actions, DESCRIPTION);
        vm.stopBroadcast();

        console.log("Proposal created by:", proposer);
        console.log("Proposal ID:", proposalId);
    }

    function buildProposalCalldata() public view returns (IVoter.Action[] memory actions) {
        uint256 borrowerReceiverId = EMISSIONS_CONTROLLER.receiverToId(Protocol.DEBT_RECEIVER);
        uint256 retentionReceiverId = EMISSIONS_CONTROLLER.receiverToId(Protocol.RETENTION_RECEIVER);

        IEmissionsController.Receiver memory borrowerReceiver = EMISSIONS_CONTROLLER.idToReceiver(borrowerReceiverId);
        IEmissionsController.Receiver memory retentionReceiver = EMISSIONS_CONTROLLER.idToReceiver(retentionReceiverId);

        require(borrowerReceiver.active && borrowerReceiver.receiver == Protocol.DEBT_RECEIVER, "unexpected borrower receiver");
        require(retentionReceiver.active && retentionReceiver.receiver == Protocol.RETENTION_RECEIVER, "unexpected retention receiver");
        require(borrowerReceiver.weight == EXPECTED_BORROWER_WEIGHT, "unexpected borrower weight");
        require(retentionReceiver.weight == EXPECTED_RETENTION_WEIGHT, "unexpected retention weight");

        uint256[] memory receiverIds = new uint256[](2);
        receiverIds[0] = borrowerReceiverId; // borrower emissions receiver
        receiverIds[1] = retentionReceiverId; // retention emissions receiver

        uint256[] memory weights = new uint256[](2);
        weights[0] = NEW_BORROWER_WEIGHT; // 25% to borrowers
        weights[1] = NEW_RETENTION_WEIGHT; // end retention emissions

        actions = new IVoter.Action[](3);

        // Reroute the retention program's 6.25% emissions share to borrowers.
        actions[0] = IVoter.Action({
            target: Protocol.EMISSIONS_CONTROLLER,
            data: abi.encodeWithSelector(
                IEmissionsController.setReceiverWeights.selector,
                receiverIds, // receiver IDs
                weights // weights in basis points
            )
        });

        // Disable the retention receiver's weekly treasury allocation.
        actions[1] = IVoter.Action({
            target: Protocol.RETENTION_RECEIVER,
            data: abi.encodeWithSelector(
                IRetentionReceiver.setTreasuryAllocationPerEpoch.selector,
                0 // weekly treasury allocation
            )
        });

        // Clear the retention receiver's treasury approval.
        actions[2] = IVoter.Action({
            target: Protocol.TREASURY,
            data: abi.encodeWithSelector(
                ITreasury.setTokenApproval.selector,
                Protocol.GOV_TOKEN, // token
                Protocol.RETENTION_RECEIVER, // spender
                0 // allowance
            )
        });
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
