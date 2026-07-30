// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol } from "src/Constants.sol";
import { IEmissionsController } from "src/interfaces/IEmissionsController.sol";
import { IRetentionReceiver } from "src/interfaces/IRetentionReceiver.sol";
import { ITreasury } from "src/interfaces/ITreasury.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { RerouteRetentionEmissions } from "script/proposals/RerouteRetentionEmissions.s.sol";
import { BaseProposalTest } from "test/integration/proposals/BaseProposalTest.sol";

contract RerouteRetentionEmissionsTest is BaseProposalTest {
    RerouteRetentionEmissions public script;

    uint256 public borrowerReceiverId;
    uint256 public insuranceReceiverId;
    uint256 public liquidityReceiverId;
    uint256 public retentionReceiverId;

    function setUp() public override {
        super.setUp();

        script = new RerouteRetentionEmissions();
        borrowerReceiverId = emissionsController.receiverToId(Protocol.DEBT_RECEIVER);
        insuranceReceiverId = emissionsController.receiverToId(Protocol.INSURANCE_POOL_RECEIVER);
        liquidityReceiverId = emissionsController.receiverToId(Protocol.LIQUIDITY_INCENTIVES_RECEIVER);
        retentionReceiverId = emissionsController.receiverToId(Protocol.RETENTION_RECEIVER);
    }

    function test_ProposalReroutesRetentionEmissionsToBorrowers() public {
        _assertReceiver(borrowerReceiverId, Protocol.DEBT_RECEIVER, script.EXPECTED_BORROWER_WEIGHT());
        _assertReceiver(retentionReceiverId, Protocol.RETENTION_RECEIVER, script.EXPECTED_RETENTION_WEIGHT());

        _executeProposal();

        _assertReceiver(borrowerReceiverId, Protocol.DEBT_RECEIVER, script.NEW_BORROWER_WEIGHT());
        _assertReceiver(insuranceReceiverId, Protocol.INSURANCE_POOL_RECEIVER, 2500);
        _assertReceiver(liquidityReceiverId, Protocol.LIQUIDITY_INCENTIVES_RECEIVER, 5000);
        _assertReceiver(retentionReceiverId, Protocol.RETENTION_RECEIVER, script.NEW_RETENTION_WEIGHT());
    }

    function test_FutureEmissionsAccrueToBorrowersNotRetention() public {
        _executeProposal();

        (, uint256 borrowerAllocationBefore) = emissionsController.allocated(Protocol.DEBT_RECEIVER);
        (, uint256 retentionAllocationBefore) = emissionsController.allocated(Protocol.RETENTION_RECEIVER);

        skip(core.epochLength());

        uint256 borrowerEmissions = debtReceiver.allocateEmissions();
        uint256 retentionEmissions = retentionReceiver.allocateEmissions();

        (, uint256 borrowerAllocationAfter) = emissionsController.allocated(Protocol.DEBT_RECEIVER);
        (, uint256 retentionAllocationAfter) = emissionsController.allocated(Protocol.RETENTION_RECEIVER);

        assertGt(borrowerEmissions, 0, "borrowers received no new emissions");
        assertEq(borrowerAllocationAfter - borrowerAllocationBefore, borrowerEmissions, "borrower allocation mismatch");
        assertEq(retentionEmissions, 0, "retention received new emissions");
        assertEq(retentionAllocationAfter, retentionAllocationBefore, "retention allocation increased");
    }

    function test_ProposalDisablesRetentionTreasuryFunding() public {
        assertEq(retentionReceiver.treasuryAllocationPerEpoch(), 34_255e18, "unexpected initial treasury allocation");
        assertEq(govToken.allowance(Protocol.TREASURY, Protocol.RETENTION_RECEIVER), type(uint256).max, "unexpected initial allowance");

        _executeProposal();

        assertEq(retentionReceiver.treasuryAllocationPerEpoch(), 0, "retention treasury allocation not cleared");
        assertEq(govToken.allowance(Protocol.TREASURY, Protocol.RETENTION_RECEIVER), 0, "retention allowance not cleared");
    }

    function test_RetentionClaimStillSucceedsAfterApprovalClearance() public {
        _executeProposal();

        skip(core.epochLength());
        retentionReceiver.claimEmissions();

        assertEq(retentionReceiver.treasuryAllocationPerEpoch(), 0, "retention treasury allocation restored");
        assertEq(govToken.allowance(Protocol.TREASURY, Protocol.RETENTION_RECEIVER), 0, "retention allowance restored");
    }

    function test_ProposalPayload() public view {
        IVoter.Action[] memory actions = script.buildProposalCalldata();
        assertEq(actions.length, 3, "unexpected action count");

        uint256[] memory receiverIds = new uint256[](2);
        receiverIds[0] = borrowerReceiverId;
        receiverIds[1] = retentionReceiverId;

        uint256[] memory weights = new uint256[](2);
        weights[0] = script.NEW_BORROWER_WEIGHT();
        weights[1] = script.NEW_RETENTION_WEIGHT();

        assertEq(actions[0].target, Protocol.EMISSIONS_CONTROLLER, "action 0 target");
        assertEq(keccak256(actions[0].data), keccak256(abi.encodeWithSelector(IEmissionsController.setReceiverWeights.selector, receiverIds, weights)), "action 0 calldata");

        assertEq(actions[1].target, Protocol.RETENTION_RECEIVER, "action 1 target");
        assertEq(keccak256(actions[1].data), keccak256(abi.encodeWithSelector(IRetentionReceiver.setTreasuryAllocationPerEpoch.selector, 0)), "action 1 calldata");

        assertEq(actions[2].target, Protocol.TREASURY, "action 2 target");
        assertEq(keccak256(actions[2].data), keccak256(abi.encodeWithSelector(ITreasury.setTokenApproval.selector, Protocol.GOV_TOKEN, Protocol.RETENTION_RECEIVER, 0)), "action 2 calldata");
    }

    function _executeProposal() internal {
        uint256 proposalId = createProposal(script.buildProposalCalldata());
        simulatePassingVote(proposalId);
        executeProposal(proposalId);
    }

    function _assertReceiver(uint256 receiverId, address expectedReceiver, uint256 expectedWeight) internal view {
        IEmissionsController.Receiver memory receiver = emissionsController.idToReceiver(receiverId);
        assertTrue(receiver.active, "receiver inactive");
        assertEq(receiver.receiver, expectedReceiver, "receiver address mismatch");
        assertEq(receiver.weight, expectedWeight, "receiver weight mismatch");
    }
}
