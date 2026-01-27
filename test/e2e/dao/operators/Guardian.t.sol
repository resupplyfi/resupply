// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol } from "src/Constants.sol";
import { Setup } from "test/e2e/Setup.sol";
import { Guardian } from "src/dao/operators/Guardian.sol";
import { ICore } from "src/interfaces/ICore.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract GuardianTest is Setup {
    Guardian public guardian;
    address[] public pairs;

    function setUp() public override {
        super.setUp();
        deployDefaultLendingPairs();
        staker.epochLength();
        guardian = new Guardian(address(core), address(registry));

        // set permissions
        setOperatorPermission(address(guardian), address(voter), IVoter.cancelProposal.selector, true);
        setOperatorPermission(address(guardian), address(voter), IVoter.updateProposalDescription.selector, true);
        setOperatorPermission(address(guardian), address(registry), IResupplyRegistry.setAddress.selector, true);
        setOperatorPermission(address(guardian), address(0), IResupplyPair.pause.selector, true);
        setOperatorPermission(address(guardian), address(core), ICore.setVoter.selector, true);

        vm.startPrank(address(core));
        guardian.setGuardian(dev);
        registry.setAddress("VOTER", address(voter));
        vm.stopPrank();

        stakeAndSkip(user1, 1_000_000e18);
        createSimpleProposal(user1);

        vm.mockCall(
            address(Protocol.REGISTRY),
            abi.encodeWithSelector(IResupplyRegistry.getAllPairAddresses.selector),
            abi.encode(registry.getAllPairAddresses())
        );
        pairs = registry.getAllPairAddresses();
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
        assertGe(testPair.borrowLimit(), 0);
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
        IResupplyPair pair1 = IResupplyPair(pairs[0]);
        IResupplyPair pair2 = IResupplyPair(pairs[1]);
        vm.startPrank(address(core));
        pair1.setBorrowLimit(100e18);
        pair2.setBorrowLimit(100e18);
        vm.stopPrank();

        vm.prank(dev);
        guardian.pauseAllPairs();
        assertEq(pair1.borrowLimit(), 0);
        assertEq(pair2.borrowLimit(), 0);
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
        guardian.revertVoter();
        (bool authorized,) = core.operatorPermissions(address(guardian), address(core), ICore.setVoter.selector);
        assertEq(authorized, true);
        assertEq(core.voter(), guardian.guardian());

        vm.prank(address(core));
        core.setVoter(address(user1));

        // revoke permission
        setOperatorPermission(address(guardian), address(core), ICore.setVoter.selector, false);
        vm.prank(dev);
        vm.expectRevert("Permission to revert voter not granted");
        guardian.revertVoter();
        assertNotEq(core.voter(), guardian.guardian());

        setOperatorPermission(address(guardian), address(core), ICore.setVoter.selector, true);
        vm.prank(dev);
        guardian.revertVoter();
        assertEq(core.voter(), guardian.guardian());
    }

    function test_ViewPermissions() public {
        (bool pausePair, bool cancelProposal, bool updateProposalDescription, bool revertVoter, bool setRegistryAddress) = guardian.viewPermissions();
        assertEq(pausePair, true, "pausePair permission not set");
        assertEq(cancelProposal, true, "cancelProposal permission not set");
        assertEq(updateProposalDescription, true, "updateProposalDescription permission not set");
        assertEq(revertVoter, true, "revertVoter permission not set");
        assertEq(setRegistryAddress, true, "setRegistryAddress permission not set");

        setOperatorPermission(address(guardian), address(core), ICore.setVoter.selector, false);
        setOperatorPermission(address(guardian), address(voter), IVoter.cancelProposal.selector, false);
        setOperatorPermission(address(guardian), address(voter), IVoter.updateProposalDescription.selector, false);
        setOperatorPermission(address(guardian), address(registry), IResupplyRegistry.setAddress.selector, false);
        setOperatorPermission(address(guardian), address(0), IResupplyPair.pause.selector, false);

        (pausePair, cancelProposal, updateProposalDescription, revertVoter, setRegistryAddress) = guardian.viewPermissions();
        assertEq(pausePair, false, "pausePair still set");
        assertEq(cancelProposal, false, "cancelProposal still set");
        assertEq(updateProposalDescription, false, "updateProposalDescription still set");
        assertEq(revertVoter, false, "revertVoter still set");
        assertEq(setRegistryAddress, false, "setRegistryAddress still set");
    }

    function test_RecoverERC20() public {
        address token = address(stablecoin);
        address _guardian = guardian.guardian();
        uint256 startBalance = IERC20(token).balanceOf(_guardian);
        deal(token, address(_guardian), 100_000e18);
        vm.prank(_guardian);
        guardian.recoverERC20(IERC20(token));
        assertGt(IERC20(token).balanceOf(_guardian), startBalance);
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