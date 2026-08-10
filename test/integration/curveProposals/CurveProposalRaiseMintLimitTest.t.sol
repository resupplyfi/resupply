// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { console } from "forge-std/console.sol";
import { Mainnet } from "src/Constants.sol";
import { BaseCurveProposalTest } from "test/integration/curveProposals/BaseCurveProposalTest.sol";
import { CurveProposalRaiseMintLimit } from "script/proposals/curve/CurveProposalRaiseMintLimit.s.sol";
import { ICurveLendOperator } from "src/interfaces/curve/ICurveLendOperator.sol";

/// @dev crvUSD ControllerFactory view-surface for the debt-ceiling getter used by the assertions
///      (ICrvusdController only declares the setter).
interface ICrvusdControllerView {
    function debt_ceiling(address _to) external view returns (uint256);
}

/// @notice Fork integration test for CurveProposalRaiseMintLimit — the 15M -> 30M sreUSD lending cap raise.
/// @dev Mirrors the house pattern of the sibling tests in this folder: build the proposal script, create
///      the vote on Curve Voting Ownership, simulate a passing vote, execute, then assert the on-chain
///      effects. Notably this proves the enacted payload is the audit-approved 604-byte ground truth
///      (keccak 0xeb4427d4…) — see test/integration/proposals/CurveProposalRaiseMintLimit.t.sol for the
///      non-fork byte regression.
///
///      newVote overloads: the deployed Voting app (impl 0xa4D1a2…) dispatches BOTH
///      newVote(bytes,string) [0xd5db2c80] and newVote(bytes,string,bool,bool) [0xf4b00513].
///      The proposal script proposes via the 2-arg overload (see proposeRaise()), so this test
///      proposes the same way. Caveat: the 2-arg overload is the legacy aragon semantics —
///      castVote=true — so the proposer is auto-voted YEA at creation (and cannot vote again),
///      unlike the 4-arg overload the sibling tests use. The custom simulate below accounts for it.
contract CurveProposalRaiseMintLimitTest is BaseCurveProposalTest {
    uint256 internal constant TARGET_CEILING = 30_000_000e18;
    uint256 internal constant INITIAL_CEILING = 15_000_000e18;
    bytes32 internal constant GROUND_TRUTH_HASH = 0xeb4427d4163ec71c65bac5601d96fa11029554ff80becf5299ec114449a86287;

    CurveProposalRaiseMintLimit internal proposalScript;
    ICurveLendOperator internal operator;
    ICrvusdControllerView internal controller;

    function setUp() public override {
        super.setUp();

        controller = ICrvusdControllerView(Mainnet.CURVE_CRVUSD_CONTROLLER);
        operator = ICurveLendOperator(Mainnet.CURVELEND_SREUSD_CRVUSD_OPERATOR);

        // Guard: if this raise is already enacted on-chain (future forks), skip — same intent as the
        // isExecuted(1237) guard in CurveProposalMintTest.t.sol, adapted because this proposal has no
        // live vote id yet.
        if (controller.debt_ceiling(Mainnet.CURVE_LENDING_FACTORY) >= TARGET_CEILING && operator.mintLimit() >= TARGET_CEILING) {
            vm.skip(true);
        }

        proposalScript = new CurveProposalRaiseMintLimit();
        bytes memory script = proposalScript.buildProposalScript();

        // Every action in the enacted script must byte-for-byte match the audit-approved payload.
        assertEq(keccak256(script), GROUND_TRUTH_HASH, "proposal script deviates from ground truth");

        // Propose via the 2-arg newVote(bytes,string) overload — the exact call the script's
        // proposeRaise() makes when the operator runs it (both overloads are live on-chain; see
        // ICurveVoting notes). Called from the test contract (not through the deployed script
        // contract) so the prank sets msg.sender = a veCRV holder.
        vm.prank(Mainnet.CONVEX_VOTEPROXY);
        uint256 proposalId = ownershipVoting.newVote(script, "Raise Lending Limit of crvUSD to the sreUSD Lending Market to 30m");

        console.log("pre  debt_ceiling(factory): %e", controller.debt_ceiling(Mainnet.CURVE_LENDING_FACTORY));
        console.log("pre  operator.mintLimit(): %e", operator.mintLimit());
        console.log("pre  operator.minted():    %e", operator.mintedAmount());

        _simulatePassingVote(proposalId);

        console.log("post debt_ceiling(factory): %e", controller.debt_ceiling(Mainnet.CURVE_LENDING_FACTORY));
        console.log("post operator.mintLimit():  %e", operator.mintLimit());
        console.log("post operator.minted():     %e", operator.mintedAmount());
    }

    /// @notice Vote the veCRV whale proxies and execute. Unlike simulatePassingProposal, this tolerates
    ///         the 2-arg newVote auto-voting the proposer (ConvexVoteProxy): canVote is true for it but
    ///         a second votePct reverts "Can't change votes", so failed votes are skipped.
    function _simulatePassingVote(uint256 proposalId) internal {
        address[3] memory voters = [Mainnet.CONVEX_VOTEPROXY, Mainnet.YEARN_VOTEPROXY, Mainnet.SD_VOTEPROXY];
        for (uint256 i = 0; i < voters.length; i++) {
            vm.prank(voters[i]);
            (bool vok,) = address(ownershipVoting).call(abi.encodeWithSignature("votePct(uint256,uint256,uint256,bool)", proposalId, 1e18, 0, false));
            if (!vok) console.log("vote skipped for voter", i);
        }
        executeOwnershipProposal(proposalId);
        (, bool executed,,,,,,,,) = ownershipVoting.getVote(proposalId);
        assertTrue(executed, "proposal did not execute");
    }

    /// @notice The debt ceiling of the CurveLendMinterFactory is raised to 30M.
    function test_debtCeilingRaisedTo30M() public view {
        assertEq(controller.debt_ceiling(Mainnet.CURVE_LENDING_FACTORY), TARGET_CEILING);
    }

    /// @notice The sreUSD operator mint limit is raised to 30M.
    function test_operatorMintLimitRaisedTo30M() public view {
        assertEq(operator.mintLimit(), TARGET_CEILING);
    }

    /// @notice The operator minted (borrowed) the incremental 15M from the minter factory to
    ///         actually deploy it into the market — not just a bookkeeping change.
    function test_operatorMintedIncrementalTo30M() public view {
        assertEq(operator.mintedAmount(), TARGET_CEILING);
        assertGt(operator.mintedAmount(), INITIAL_CEILING);
    }
}
