// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol } from "src/Constants.sol";
import { BaseProposalTest } from "test/integration/proposals/BaseProposalTest.sol";
import { AddLifiSwapper } from "script/proposals/AddLifiSwapper.s.sol";
import { SwapperLifi } from "src/protocol/SwapperLifi.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { ISwapperLifi } from "src/interfaces/ISwapperLifi.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AddLifiSwapperTest is BaseProposalTest {
    AddLifiSwapper public script;
    address public lifiSwapper;
    address[] public defaultSwappersBefore;

    function setUp() public override {
        super.setUp();
        script = new AddLifiSwapper();
        lifiSwapper = address(new SwapperLifi(address(core)));
        script.setLifiSwapper(lifiSwapper);
        defaultSwappersBefore = script.getDefaultSwappers();

        IVoter.Action[] memory actions = script.buildProposalCalldata();
        uint256 proposalId = createProposal(actions);
        simulatePassingVote(proposalId);
        executeProposal(proposalId);
    }

    function test_RegistryKeySet() public view {
        assertEq(registry.getAddress(script.REGISTRY_KEY()), lifiSwapper, "wrong registry key");
    }

    function test_DefaultSwappersAreArrayAndLifiIsAppended() public view {
        address[] memory defaultSwappersAfter = script.getDefaultSwappers();
        assertEq(defaultSwappersAfter.length, defaultSwappersBefore.length + 1, "wrong default swapper count");
        for (uint256 i = 0; i < defaultSwappersBefore.length; i++) {
            assertEq(defaultSwappersAfter[i], defaultSwappersBefore[i], "existing default changed");
        }
        assertEq(defaultSwappersAfter[defaultSwappersAfter.length - 1], lifiSwapper, "LI.FI not appended");
    }

    function test_LifiWhitelistedOnExistingPairs() public view {
        for (uint256 i = 0; i < pairs.length; i++) {
            assertTrue(IResupplyPair(pairs[i]).swappers(lifiSwapper), "LI.FI not whitelisted");
        }
    }

    function test_DeployerCanRevokeApprovals() public view {
        (bool authorized,) = core.operatorPermissions(Protocol.DEPLOYER, lifiSwapper, ISwapperLifi.revokeApprovals.selector);
        assertTrue(authorized, "revoke permission not granted");
    }

    function test_ApprovalsUpdated() public view {
        address lifiRouter = SwapperLifi(lifiSwapper).lifiRouter();
        assertEq(IERC20(SwapperLifi(lifiSwapper).reusd()).allowance(lifiSwapper, lifiRouter), type(uint256).max, "reUSD approval missing");
        for (uint256 i = 0; i < pairs.length; i++) {
            address collateral = IResupplyPair(pairs[i]).collateral();
            assertEq(IERC20(collateral).allowance(lifiSwapper, lifiRouter), type(uint256).max, "collateral approval missing");
        }
    }
}
