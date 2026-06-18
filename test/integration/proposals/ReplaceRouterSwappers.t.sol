// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol } from "src/Constants.sol";
import { BaseProposalTest } from "test/integration/proposals/BaseProposalTest.sol";
import { ReplaceRouterSwappers } from "script/proposals/ReplaceRouterSwappers.s.sol";
import { RouterSwapper } from "src/protocol/swappers/RouterSwapper.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IRouterSwapper } from "src/interfaces/IRouterSwapper.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ReplaceRouterSwappersTest is BaseProposalTest {
    address public constant ODOS_ROUTER = 0xCf5540fFFCdC3d510B18bFcA6d2b9987b0772559;
    address public constant LIFI_ROUTER = 0x1231DEB6f5749EF6cE6943a275A1D3E7486F4EaE;
    address public constant ENSO_ROUTER = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf;

    ReplaceRouterSwappers public proposal;
    RouterSwapper public odosSwapper;
    RouterSwapper public lifiSwapper;
    RouterSwapper public ensoSwapper;
    address public oldOdosSwapper;
    address[] public defaultSwappersBefore;

    function setUp() public override {
        super.setUp();

        oldOdosSwapper = registry.getAddress("SWAPPER_ODOS");
        odosSwapper = new RouterSwapper(address(core), ODOS_ROUTER, "Resupply Swapper: ODOS");
        lifiSwapper = new RouterSwapper(address(core), LIFI_ROUTER, "Resupply Swapper: LI.FI");
        ensoSwapper = new RouterSwapper(address(core), ENSO_ROUTER, "Resupply Swapper: ENSO");
        odosSwapper.updateApprovals();
        lifiSwapper.updateApprovals();
        ensoSwapper.updateApprovals();
        proposal = new ReplaceRouterSwappers(oldOdosSwapper, address(odosSwapper), address(lifiSwapper), address(ensoSwapper));
        defaultSwappersBefore = proposal.getDefaultSwappers();

        IVoter.Action[] memory actions = proposal.buildProposalCalldata();
        uint256 proposalId = createProposal(actions);
        simulatePassingVote(proposalId);
        executeProposal(proposalId);
    }

    function test_RegistryKeysSet() public view {
        assertEq(registry.getAddress(proposal.SWAPPER_ODOS_KEY()), address(odosSwapper), "wrong ODOS registry key");
        assertEq(registry.getAddress(proposal.SWAPPER_LIFI_KEY()), address(lifiSwapper), "wrong LI.FI registry key");
        assertEq(registry.getAddress(proposal.SWAPPER_ENSO_KEY()), address(ensoSwapper), "wrong ENSO registry key");
    }

    function test_DefaultSwappersReplaceOldOdosAndAddProviderSet() public view {
        address[] memory defaultSwappersAfter = proposal.getDefaultSwappers();
        assertFalse(_contains(defaultSwappersAfter, oldOdosSwapper), "old ODOS still default");
        assertTrue(_contains(defaultSwappersAfter, address(odosSwapper)), "replacement ODOS not default");
        assertTrue(_contains(defaultSwappersAfter, address(lifiSwapper)), "LI.FI not default");
        assertTrue(_contains(defaultSwappersAfter, address(ensoSwapper)), "ENSO not default");

        uint256 expectedLength = 3;
        for (uint256 i = 0; i < defaultSwappersBefore.length; i++) {
            if (defaultSwappersBefore[i] == oldOdosSwapper) continue;
            if (defaultSwappersBefore[i] == address(odosSwapper)) continue;
            if (defaultSwappersBefore[i] == address(lifiSwapper)) continue;
            if (defaultSwappersBefore[i] == address(ensoSwapper)) continue;
            expectedLength++;
            assertTrue(_contains(defaultSwappersAfter, defaultSwappersBefore[i]), "existing non-provider default removed");
        }
        assertEq(defaultSwappersAfter.length, expectedLength, "wrong default swapper count");
    }

    function test_ProviderSwappersWhitelistedAndOldOdosRemoved() public view {
        for (uint256 i = 0; i < pairs.length; i++) {
            assertFalse(IResupplyPair(pairs[i]).swappers(oldOdosSwapper), "old ODOS still whitelisted");
            assertTrue(IResupplyPair(pairs[i]).swappers(address(odosSwapper)), "replacement ODOS not whitelisted");
            assertTrue(IResupplyPair(pairs[i]).swappers(address(lifiSwapper)), "LI.FI not whitelisted");
            assertTrue(IResupplyPair(pairs[i]).swappers(address(ensoSwapper)), "ENSO not whitelisted");
        }
    }

    function test_GuardianCanRevokeProviderApprovals() public view {
        assertTrue(_canGuardianRevoke(address(odosSwapper)), "ODOS revoke permission not granted");
        assertTrue(_canGuardianRevoke(address(lifiSwapper)), "LI.FI revoke permission not granted");
        assertTrue(_canGuardianRevoke(address(ensoSwapper)), "ENSO revoke permission not granted");
    }

    function test_ApprovalsUpdated() public view {
        _assertApprovals(address(odosSwapper), odosSwapper.router());
        _assertApprovals(address(lifiSwapper), lifiSwapper.router());
        _assertApprovals(address(ensoSwapper), ensoSwapper.router());
    }

    function _assertApprovals(address swapper, address router) internal view {
        assertEq(IERC20(IRouterSwapper(swapper).reusd()).allowance(swapper, router), type(uint256).max, "reUSD approval missing");
        for (uint256 i = 0; i < pairs.length; i++) {
            address collateral = IResupplyPair(pairs[i]).collateral();
            assertEq(IERC20(collateral).allowance(swapper, router), type(uint256).max, "collateral approval missing");
        }
    }

    function _canGuardianRevoke(address swapper) internal view returns (bool authorized) {
        (authorized,) = core.operatorPermissions(Protocol.OPERATOR_GUARDIAN_PROXY, swapper, IRouterSwapper.revokeApprovals.selector);
    }

    function _contains(address[] memory addresses, address target) internal pure returns (bool) {
        for (uint256 i = 0; i < addresses.length; i++) {
            if (addresses[i] == target) return true;
        }
        return false;
    }
}
