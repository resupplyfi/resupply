// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol } from "src/Constants.sol";
import { BaseProposalTest } from "test/integration/proposals/BaseProposalTest.sol";
import { ReplaceRouterSwappers } from "script/proposals/ReplaceRouterSwappers.s.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IRouterSwapper } from "src/interfaces/IRouterSwapper.sol";
import { IGuardianUpgradeable } from "src/interfaces/IGuardianUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ReplaceRouterSwappersTest is BaseProposalTest {
    address public constant ODOS_ROUTER = 0x0D05a7D3448512B78fa8A9e46c4872C88C4a0D05;
    address public constant OLD_ODOS_ROUTER = 0xCf5540fFFCdC3d510B18bFcA6d2b9987b0772559;
    address public constant LIFI_ROUTER = 0x1231DEB6f5749EF6cE6943a275A1D3E7486F4EaE;
    address public constant ENSO_ROUTER = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf;

    ReplaceRouterSwappers public proposal;
    address public odosSwapper;
    address public lifiSwapper;
    address public ensoSwapper;
    address public oldOdosSwapper;
    address[] public defaultSwappersBefore;

    function setUp() public override {
        super.setUp();

        oldOdosSwapper = Protocol.SWAPPER_ODOS;
        proposal = new ReplaceRouterSwappers();
        odosSwapper = proposal.odosSwapper();
        lifiSwapper = proposal.lifiSwapper();
        ensoSwapper = proposal.ensoSwapper();
        defaultSwappersBefore = proposal.getDefaultSwappers();

        IVoter.Action[] memory actions = proposal.buildProposalCalldata();
        uint256 proposalId = createProposal(actions);
        simulatePassingVote(proposalId);
        executeProposal(proposalId);
    }

    function test_RegistryKeysSet() public view {
        assertEq(registry.getAddress(proposal.SWAPPER_ODOS_KEY()), odosSwapper, "wrong ODOS registry key");
        assertEq(registry.getAddress(proposal.SWAPPER_LIFI_KEY()), lifiSwapper, "wrong LI.FI registry key");
        assertEq(registry.getAddress(proposal.SWAPPER_ENSO_KEY()), ensoSwapper, "wrong ENSO registry key");
    }

    function test_DefaultSwappersAreOriginalDefaultPlusProviderSet() public view {
        address[] memory defaultSwappersAfter = proposal.getDefaultSwappers();
        assertEq(defaultSwappersAfter.length, 4, "wrong default swapper count");
        assertEq(defaultSwappersAfter[0], defaultSwappersBefore[0], "original default changed");
        assertEq(defaultSwappersAfter[1], odosSwapper, "replacement ODOS not default");
        assertEq(defaultSwappersAfter[2], lifiSwapper, "LI.FI not default");
        assertEq(defaultSwappersAfter[3], ensoSwapper, "ENSO not default");
    }

    function test_ProviderSwappersWhitelistedAndOldOdosRemoved() public view {
        for (uint256 i = 0; i < pairs.length; i++) {
            assertFalse(IResupplyPair(pairs[i]).swappers(oldOdosSwapper), "old ODOS still whitelisted");
            assertTrue(IResupplyPair(pairs[i]).swappers(odosSwapper), "replacement ODOS not whitelisted");
            assertTrue(IResupplyPair(pairs[i]).swappers(lifiSwapper), "LI.FI not whitelisted");
            assertTrue(IResupplyPair(pairs[i]).swappers(ensoSwapper), "ENSO not whitelisted");
        }
    }

    function test_GuardianCanRevokeProviderApprovalsViaWildcardPermission() public view {
        (bool wildcardAuthorized,) = core.operatorPermissions(
            Protocol.OPERATOR_GUARDIAN_PROXY,
            address(0),
            IRouterSwapper.revokeApprovals.selector
        );
        assertTrue(wildcardAuthorized, "guardian revoke permission not wildcarded");

        assertFalse(_hasTargetSpecificGuardianRevokePermission(odosSwapper), "ODOS revoke should use wildcard");
        assertFalse(_hasTargetSpecificGuardianRevokePermission(lifiSwapper), "LI.FI revoke should use wildcard");
        assertFalse(_hasTargetSpecificGuardianRevokePermission(ensoSwapper), "ENSO revoke should use wildcard");

        IGuardianUpgradeable guardian = IGuardianUpgradeable(Protocol.OPERATOR_GUARDIAN_PROXY);
        assertTrue(
            guardian.hasPermission(odosSwapper, IRouterSwapper.revokeApprovals.selector),
            "guardian cannot revoke ODOS approvals"
        );
        assertTrue(
            guardian.hasPermission(lifiSwapper, IRouterSwapper.revokeApprovals.selector),
            "guardian cannot revoke LI.FI approvals"
        );
        assertTrue(
            guardian.hasPermission(ensoSwapper, IRouterSwapper.revokeApprovals.selector),
            "guardian cannot revoke ENSO approvals"
        );
    }

    function test_ApprovalsUpdated() public view {
        _assertApprovals(odosSwapper, IRouterSwapper(odosSwapper).router());
        _assertApprovals(lifiSwapper, IRouterSwapper(lifiSwapper).router());
        _assertApprovals(ensoSwapper, IRouterSwapper(ensoSwapper).router());
    }

    function test_OldOdosApprovalsRevoked() public view {
        assertEq(IERC20(Protocol.STABLECOIN).allowance(oldOdosSwapper, OLD_ODOS_ROUTER), 0, "old reUSD approval remains");
        for (uint256 i = 0; i < pairs.length; i++) {
            address collateral = IResupplyPair(pairs[i]).collateral();
            assertEq(IERC20(collateral).allowance(oldOdosSwapper, OLD_ODOS_ROUTER), 0, "old collateral approval remains");
        }
        assertTrue(IRouterSwapper(oldOdosSwapper).approvalsRevoked(), "old ODOS approvals not marked revoked");
    }

    function _assertApprovals(address swapper, address router) internal view {
        assertEq(IERC20(IRouterSwapper(swapper).reusd()).allowance(swapper, router), type(uint256).max, "reUSD approval missing");
        for (uint256 i = 0; i < pairs.length; i++) {
            address collateral = IResupplyPair(pairs[i]).collateral();
            assertEq(IERC20(collateral).allowance(swapper, router), type(uint256).max, "collateral approval missing");
        }
    }

    function _hasTargetSpecificGuardianRevokePermission(address swapper) internal view returns (bool authorized) {
        (authorized,) = core.operatorPermissions(Protocol.OPERATOR_GUARDIAN_PROXY, swapper, IRouterSwapper.revokeApprovals.selector);
    }

    function _contains(address[] memory addresses, address target) internal pure returns (bool) {
        for (uint256 i = 0; i < addresses.length; i++) {
            if (addresses[i] == target) return true;
        }
        return false;
    }
}
