// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol } from "src/Constants.sol";
import { BaseProposalTest } from "test/integration/proposals/BaseProposalTest.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { ProposeUnpause } from "script/proposals/ProposeUnpause.s.sol";

contract ProposeUnpauseTest is BaseProposalTest {
    ProposeUnpause public script;
    IResupplyPair public pair;
    uint256 public proposalId;

    function setUp() public override {
        super.setUp();
        script = new ProposeUnpause();
        pair = IResupplyPair(Protocol.PAIR_CURVELEND_SFRXUSD_CRVUSD);

        proposalId = createProposal(script.buildProposalCalldata());
        simulatePassingVote(proposalId);
        executeProposal(proposalId);
    }

    function test_BorrowLimitRestoredAfterUnpause() public {
        assertGt(pair.borrowLimit(), 0, "Borrow limit should be > 0");
    }
}