// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol } from "src/Constants.sol";
import { FixRouterSwapperMemory } from "script/proposals/FixRouterSwapperMemory.s.sol";
import { BaseProposalTest } from "test/integration/proposals/BaseProposalTest.sol";
import { RouterSwapper } from "src/protocol/swappers/RouterSwapper.sol";
import { IRouterSwapper } from "src/interfaces/IRouterSwapper.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IGuardianUpgradeable } from "src/interfaces/IGuardianUpgradeable.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract FixRouterSwapperMemoryTest is BaseProposalTest {
    uint256 internal constant FORK_BLOCK = 26_083_817;
    FixRouterSwapperMemory internal script;
    RouterSwapper internal ensoSwapper;
    RouterSwapper internal lifiSwapper;
    address internal odosSwapper;

    function setUp() public override {
        vm.createSelectFork(vm.envString("MAINNET_URL"), FORK_BLOCK);
        pairs = registry.getAllPairAddresses();
        script = new FixRouterSwapperMemory();
        ensoSwapper = new RouterSwapper(Protocol.CORE, IRouterSwapper(script.OLD_ENSO_SWAPPER()).router(), "Resupply Swapper: ENSO");
        lifiSwapper = new RouterSwapper(Protocol.CORE, IRouterSwapper(script.OLD_LIFI_SWAPPER()).router(), "Resupply Swapper: LI.FI");
        odosSwapper = registry.getAddress("SWAPPER_ODOS");
    }

    function test_ProposalReplacesActiveSwappers() public {
        address[] memory expectedDefaults = script.buildDefaultSwappers(address(ensoSwapper), address(lifiSwapper));
        assertTrue(IRouterSwapper(odosSwapper).approvalsRevoked(), "ODOS should already be revoked");
        assertEq(expectedDefaults.length, 4);
        assertEq(expectedDefaults[0], registry.defaultSwappers(0), "original default changed");
        assertEq(expectedDefaults[1], odosSwapper, "ODOS default changed");
        assertEq(expectedDefaults[2], address(lifiSwapper));
        assertEq(expectedDefaults[3], address(ensoSwapper));

        IVoter.Action[] memory actions = script.buildProposalCalldata(address(ensoSwapper), address(lifiSwapper));
        assertEq(actions.length, 7 + pairs.length * 4);
        uint256 gasBefore = gasleft();
        uint256 proposalId = createProposal(actions);
        assertLt(gasBefore - gasleft(), 15_000_000, "proposal creation gas too high");
        simulatePassingVote(proposalId);
        skip(voter.executionDelay());
        gasBefore = gasleft();
        voter.executeProposal(proposalId);
        assertLt(gasBefore - gasleft(), 15_000_000, "proposal execution gas too high");
        assertTrue(isProposalProcessed(proposalId));

        assertEq(registry.getAddress("SWAPPER_ENSO"), address(ensoSwapper));
        assertEq(registry.getAddress("SWAPPER_LIFI"), address(lifiSwapper));
        assertEq(registry.getAddress("SWAPPER_ODOS"), odosSwapper);
        assertTrue(IRouterSwapper(odosSwapper).approvalsRevoked(), "ODOS was re-enabled");
        for (uint256 i; i < expectedDefaults.length; i++) {
            assertEq(registry.defaultSwappers(i), expectedDefaults[i]);
        }
        vm.expectRevert();
        registry.defaultSwappers(expectedDefaults.length);

        _assertReplacement(script.OLD_ENSO_SWAPPER(), ensoSwapper);
        _assertReplacement(script.OLD_LIFI_SWAPPER(), lifiSwapper);
    }

    function test_ProposalRejectsInvalidReplacements() public {
        address oldEnsoSwapper = script.OLD_ENSO_SWAPPER();
        vm.expectRevert("Invalid replacement");
        script.buildProposalCalldata(oldEnsoSwapper, address(lifiSwapper));
        vm.expectRevert("Invalid replacement");
        script.buildProposalCalldata(address(0), address(lifiSwapper));
        vm.expectRevert("Wrong replacement router");
        script.buildProposalCalldata(address(lifiSwapper), address(ensoSwapper));

        RouterSwapper wrongOwner = new RouterSwapper(address(this), ensoSwapper.router(), "Wrong owner");
        vm.expectRevert("Wrong replacement owner");
        script.buildProposalCalldata(address(wrongOwner), address(lifiSwapper));

        vm.prank(Protocol.CORE);
        ensoSwapper.revokeApprovals();
        vm.expectRevert("Replacement revoked");
        script.buildProposalCalldata(address(ensoSwapper), address(lifiSwapper));
    }

    function test_ProposalRejectsChangedCurrentSwapper() public {
        vm.prank(Protocol.CORE);
        registry.setAddress("SWAPPER_ENSO", address(ensoSwapper));
        vm.expectRevert("Current swapper changed");
        script.buildProposalCalldata(address(ensoSwapper), address(lifiSwapper));
    }

    function test_LargeRouteDecodingAgainstDeployedSwappers() public view {
        bytes memory payload = new bytes(14_600);
        address[] memory path = ensoSwapper.encode(payload, address(1), address(2));
        bytes memory callData = abi.encodeCall(IRouterSwapper.decode, (path));
        address[2] memory oldSwappers = [script.OLD_ENSO_SWAPPER(), script.OLD_LIFI_SWAPPER()];
        address[2] memory replacements = [address(ensoSwapper), address(lifiSwapper)];
        for (uint256 i; i < oldSwappers.length; i++) {
            (bool oldSuccess, bytes memory oldResult) = oldSwappers[i].staticcall{ gas: 2_000_000 }(callData);
            assertFalse(oldSuccess, "deployed decoder should exhaust the budget");
            assertEq(oldResult.length, 0, "unexpected revert data");
            (bool success, bytes memory result) = replacements[i].staticcall{ gas: 2_000_000 }(callData);
            assertTrue(success, "replacement exhausted the same budget");
            assertEq(result, abi.encode(payload));
        }
    }

    function _assertReplacement(address oldSwapper, RouterSwapper replacement) internal view {
        assertTrue(IRouterSwapper(oldSwapper).approvalsRevoked());
        assertFalse(replacement.approvalsRevoked());
        assertFalse(replacement.canUpdateApprovals());
        assertEq(replacement.nextPairIndex(), pairs.length);
        address router = replacement.router();
        assertEq(IERC20(Protocol.STABLECOIN).allowance(oldSwapper, router), 0);
        assertEq(IERC20(Protocol.STABLECOIN).allowance(address(replacement), router), type(uint256).max);
        for (uint256 i; i < pairs.length; i++) {
            IResupplyPair pair = IResupplyPair(pairs[i]);
            assertFalse(pair.swappers(oldSwapper));
            assertTrue(pair.swappers(address(replacement)));
            assertTrue(pair.swappers(odosSwapper), "existing ODOS whitelist changed");
            assertTrue(pair.swappers(Protocol.SWAPPER), "base swapper removed");
            assertEq(IERC20(pair.collateral()).allowance(oldSwapper, router), 0);
            assertEq(IERC20(pair.collateral()).allowance(address(replacement), router), type(uint256).max);
        }
        assertTrue(IGuardianUpgradeable(Protocol.OPERATOR_GUARDIAN_PROXY).hasPermission(address(replacement), IRouterSwapper.revokeApprovals.selector), "guardian cannot revoke replacement");
    }
}
