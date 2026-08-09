// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "lib/forge-std/src/Test.sol";
import { Mainnet } from "src/Constants.sol";
import { ICrvusdController } from "src/interfaces/ICrvusdController.sol";
import { ICurveLendMinterFactory } from "src/interfaces/ICurveLendMinterFactory.sol";
import { CurveProposalRaiseMintLimit } from "script/proposals/curve/CurveProposalRaiseMintLimit.s.sol";

/// @notice Regression tests for the 15M -> 30M sreUSD lending cap proposal script.
/// @dev Ground-truth execution script is the fork-proven payload (604 bytes):
///      outer 0x00000001 + [agent][len][data] x2, eDAO-proxy-wrapped set_debt_ceiling(30M)
///      then operator setMintLimit(30M). Fingerprints:
///      keccak 0xeb4427d4163ec71c65bac5601d96fa11029554ff80becf5299ec114449a86287
contract CurveProposalRaiseMintLimitReviewTest is Test {
    bytes internal constant GROUND_TRUTH =
        hex"0000000140907540d8a6c65c637785e8f8b742ae6b0b996800000164b61d27f6000000000000000000000000b7400d2ea0f6dc1d7b153aa430b9e572f28afb790000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000c41cff79cd000000000000000000000000c9332fdcb1c491dcc683bae86fe3cb70360738bc00000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000044b933c50a000000000000000000000000d99391df68cdb38a89828a6d51f3976e3e76afff00000000000000000000000000000000000000000018d0bf423c03d8de000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000040907540d8a6c65c637785e8f8b742ae6b0b9968000000c4b61d27f600000000000000000000000021862ca8d044c104ac9eb728c86bc38b8625becd0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000249e6a1d7d00000000000000000000000000000000000000000018d0bf423c03d8de00000000000000000000000000000000000000000000000000000000000000";

    CurveProposalRaiseMintLimit internal proposal;

    function setUp() public {
        proposal = new CurveProposalRaiseMintLimit();
    }

    function testBuildProposalScriptMatchesGroundTruthExactly() public {
        vm.mockCall(
            Mainnet.CURVE_CRVUSD_CONTROLLER,
            abi.encodeWithSelector(ICrvusdController.admin.selector),
            abi.encode(Mainnet.CURVE_MINT_FACTORY_EDAO_ADMIN_PROXY)
        );

        bytes memory actual = proposal.buildProposalScript();
        assertEq(actual.length, 604);
        assertEq(actual, GROUND_TRUTH);
        assertEq(keccak256(actual), 0xeb4427d4163ec71c65bac5601d96fa11029554ff80becf5299ec114449a86287);
    }

    function testBuildProposalScriptRejectsWrongControllerAdmin() public {
        vm.mockCall(
            Mainnet.CURVE_CRVUSD_CONTROLLER,
            abi.encodeWithSelector(ICrvusdController.admin.selector),
            abi.encode(address(0xdead))
        );
        vm.expectRevert("Target is not admin of EDAO proxy");
        proposal.buildProposalScript();
    }
}
