// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Setup } from "test/Setup.sol";
import { Guardian } from "src/dao/operators/Guardian.sol";
import { ICore } from "src/interfaces/ICore.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IAuthHook } from "src/interfaces/IAuthHook.sol";

contract GuardianTest is Setup {
    Guardian public guardian;

    function setUp() public override {
        super.setUp();
        deployDefaultLendingPairs();
        staker.epochLength();
        guardian = new Guardian(address(core), address(registry));
        vm.startPrank(address(core));
        core.setOperatorPermissions(
            address(guardian), 
            address(0), // can call on any target
            IResupplyPair.pause.selector,
            true,
            IAuthHook(address(0)) // auth hook
        );
        core.setOperatorPermissions(
            address(guardian),    // caller
            address(voter),       // target
            IVoter.cancelProposal.selector,
            true,
            IAuthHook(address(0)) // auth hook
        );
        guardian.setGuardian(dev);
        registry.setAddress("VOTER", address(voter));
        vm.stopPrank();

        stakeAndSkip(user1, 1_000_000e18);
        createSimpleProposal(user1);
    }

    function test_SetGuardian() public {
        address newGuardian = address(0xDAD);
        vm.expectRevert("!core");
        guardian.setGuardian(newGuardian);
        assertNotEq(guardian.guardian(), newGuardian);

        vm.prank(address(core));
        guardian.setGuardian(newGuardian);
        assertEq(guardian.guardian(), newGuardian);
    }

    function test_SetGuardianNotOwner() public {
        vm.prank(address(0xBABE));
        vm.expectRevert("!core");
        guardian.setGuardian(address(0xDAD));
    }

    function test_PausePair() public {
        assertGt(testPair.borrowLimit(), 0);
        vm.prank(dev);
        guardian.pausePair(address(testPair));
        assertEq(testPair.borrowLimit(), 0);
    }

    function test_PausePairNotGuardian() public {
        vm.prank(address(0xBABE));
        vm.expectRevert("!guardian");
        guardian.pausePair(address(testPair));
    }

    function test_PauseAllPairs() public {
        assertGt(testPair.borrowLimit(), 0);
        assertGt(testPair2.borrowLimit(), 0);
        vm.prank(dev);
        guardian.pauseAllPairs();
        assertEq(testPair.borrowLimit(), 0);
        assertEq(testPair2.borrowLimit(), 0);
    }

    function test_PauseAllPairsNotGuardian() public {
        vm.prank(address(0xBABE));
        vm.expectRevert("!guardian");
        guardian.pauseAllPairs();
    }

    function test_CancelProposal() public {
        uint256 proposalId = 0;
        (,,,bool processed,) = IVoter(address(voter)).proposalData(proposalId);
        assertEq(processed, false);

        vm.prank(address(0xBABE));
        vm.expectRevert("!guardian");
        guardian.cancelProposal(0);

        vm.prank(dev);
        guardian.cancelProposal(proposalId);
        (,,,processed,) = IVoter(address(voter)).proposalData(proposalId);
        assertEq(processed, true);
    }

    function test_VoterRevert() public {
        vm.prank(dev);
        vm.expectRevert("Permission to revert voter not granted");
        guardian.revertVoter();
        (bool authorized,) = core.operatorPermissions(address(guardian), address(core), ICore.setVoter.selector);
        assertEq(authorized, false);

        vm.prank(address(core));
        core.setOperatorPermissions(
            address(guardian),
            address(core),
            ICore.setVoter.selector,
            true,
            IAuthHook(address(0))
        );
        assertNotEq(core.voter(), guardian.guardian());

        vm.prank(dev);
        guardian.revertVoter();
        (authorized,) = core.operatorPermissions(address(guardian), address(core), ICore.setVoter.selector);
        assertEq(authorized, true);
        assertEq(core.voter(), guardian.guardian());

        vm.startPrank(address(core));
        // set voter to to something else and revoke permission
        core.setVoter(address(user1)); 
        core.setOperatorPermissions(
            address(guardian),
            address(core),
            ICore.setVoter.selector,
            false,
            IAuthHook(address(0))
        );
        vm.stopPrank();

        vm.prank(dev);
        vm.expectRevert("Permission to revert voter not granted");
        guardian.revertVoter();
    }

    function createSimpleProposal(address account) public returns (uint256) {
        IVoter.Action[] memory payload = new IVoter.Action[](1);
        payload[0] = IVoter.Action({
            target: address(stablecoin),
            data: abi.encodeWithSelector(
                IERC20.approve.selector, 
                address(testPair),
                type(uint256).max
            )
        });
        vm.prank(account);
        return IVoter(address(voter)).createNewProposal(account, payload, 'Test Proposal');
    }

    function stakeAndSkip(address account, uint256 amount) public {
        deal(address(govToken), account, amount);
        vm.startPrank(account);
        govToken.approve(address(staker), amount);
        staker.stake(account, amount);
        skip(staker.epochLength() * 2);
        vm.stopPrank();
    }
}