// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { console } from "forge-std/console.sol";
import { Protocol } from "src/Constants.sol";
import { GuardianUpgradeable } from "src/dao/operators/GuardianUpgradeable.sol";
import { Upgrades, UnsafeUpgrades } from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import { Options } from "@openzeppelin/foundry-upgrades/Options.sol";
import { BaseUpgradeableOperatorTest } from "test/utils/BaseUpgradeableOperator.sol";
import { Setup } from "test/e2e/Setup.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { Voter } from "src/dao/Voter.sol";
import { ICore } from "src/interfaces/ICore.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IAuthHook } from "src/interfaces/IAuthHook.sol";

contract GuardianUpgradeableTest is Setup, BaseUpgradeableOperatorTest {
    address public guardian = Protocol.DEPLOYER;
    GuardianUpgradeable public guardianContract;
    IResupplyPair public pair;

    event GuardianSet(address indexed newGuardian);
    event PairPaused(address indexed pair);

    function setUp() public override {
        super.setUp();
        deployProxyAndImplementation();
        guardianContract = GuardianUpgradeable(proxy);
        setupPermissions();
        pair = IResupplyPair(registry.getAllPairAddresses()[0]);
        stakeGovToken(1000e18);
        skip(epochLength);
    }

    // Implement abstract functions from BaseUpgradeableOperatorTest
    function initialize() internal override {GuardianUpgradeable(proxy).initialize(guardian);}
    function getContractNameV1() internal view override returns (string memory) {return "GuardianUpgradeable.sol:GuardianUpgradeable";}
    function getContractNameV2() internal view override returns (string memory) {return "GuardianUpgradeable.sol:GuardianUpgradeable";}
    function getInitializerData() internal view override returns (bytes memory) {return abi.encodeCall(GuardianUpgradeable.initialize, guardian);}

    function setupPermissions() internal {
        setOperatorPermission(address(guardianContract), address(0), IResupplyPair.pause.selector, true);
        setOperatorPermission(address(guardianContract), address(0), Voter.cancelProposal.selector, true);
        setOperatorPermission(address(guardianContract), address(0), Voter.updateProposalDescription.selector, true);
        setOperatorPermission(address(guardianContract), address(core), ICore.setVoter.selector, true);
        setOperatorPermission(address(guardianContract), address(registry), IResupplyRegistry.setAddress.selector, true);
    }

    function test_GuardianSet() public {
        assertEq(guardianContract.guardian(), guardian);
    }

    function test_GuardianSet_NotOwner() public {
        vm.prank(address(1));
        vm.expectRevert("!owner");
        guardianContract.setGuardian(address(1));
    }

    function test_SetGuardian() public {
        address newGuardian = address(0x999);
        vm.expectEmit(true, false, false, true);
        emit GuardianSet(newGuardian);
        guardianContract.setGuardian(newGuardian);
        assertEq(guardianContract.guardian(), newGuardian);
    }

    function test_PauseAllPairs() public {
        // Add some pairs to the registry first
        vm.prank(address(core));
        registry.addPair(address(pair));
        
        // Add another pair for testing
        address pair2 = address(0x222);
        vm.prank(address(core));
        registry.addPair(pair2);

        vm.expectEmit(true, false, false, true);
        emit PairPaused(address(pair));
        vm.expectEmit(true, false, false, true);
        emit PairPaused(pair2);

        vm.prank(guardian);
        guardianContract.pauseAllPairs();
    }

    function test_PauseAllPairs_NotGuardian() public {
        vm.prank(address(1));
        vm.expectRevert("!guardian");
        guardianContract.pauseAllPairs();
    }

    function test_PausePair() public {
        vm.expectEmit(true, false, false, true);
        emit PairPaused(address(pair));

        vm.prank(guardian);
        guardianContract.pausePair(address(pair));
    }

    function test_PausePair_NotGuardian() public {
        vm.prank(address(1));
        vm.expectRevert("!guardian");
        guardianContract.pausePair(address(pair));
    }

    function test_CancelProposal() public {
        Voter.Action[] memory actions = new Voter.Action[](1);
        actions[0] = Voter.Action({
            target: address(pair),
            data: abi.encodeWithSelector(IResupplyPair.pause.selector)
        });
        uint256 proposalId = voter.createNewProposal(
            address(this),
            actions,
            "Test proposal"
        );

        assertTrue(guardianContract.hasPermission(address(voter), Voter.cancelProposal.selector));
        vm.prank(guardian);
        guardianContract.cancelProposal(proposalId);
    }

    function test_CancelProposal_NotGuardian() public {
        vm.prank(address(1));
        vm.expectRevert("!guardian");
        guardianContract.cancelProposal(123);
    }

    function test_UpdateProposalDescription() public {
        Voter.Action[] memory actions = new Voter.Action[](1);
        actions[0] = Voter.Action({
            target: address(pair),
            data: abi.encodeWithSelector(IResupplyPair.pause.selector)
        });
        uint256 proposalId = voter.createNewProposal(
            address(this),
            actions,
            "Original description"
        );

        string memory newDescription = "Updated description";
        vm.prank(guardian);
        guardianContract.updateProposalDescription(proposalId, newDescription);
        
        // Verify the description was updated
        assertEq(voter.proposalDescription(proposalId), newDescription);
    }

    function test_UpdateProposalDescription_NotGuardian() public {
        vm.prank(address(1));
        vm.expectRevert("!guardian");
        guardianContract.updateProposalDescription(123, "description");
    }

    function test_RevertVoter() public {
        address currentVoter = address(voter);
        
        vm.prank(guardian);
        guardianContract.revertVoter();
        
        // Verify the voter was set to guardian
        assertEq(core.voter(), guardian);
    }

    function test_RevertVoter_NotGuardian() public {
        vm.prank(address(1));
        vm.expectRevert("!guardian");
        guardianContract.revertVoter();
    }

    function test_RevertVoter_NoPermission() public {
        // Remove the permission
        vm.prank(address(core));
        core.setOperatorPermissions(
            address(guardianContract),
            address(core),
            ICore.setVoter.selector,
            false,
            IAuthHook(address(0))
        );

        vm.prank(guardian);
        vm.expectRevert("Permission to revert voter not granted");
        guardianContract.revertVoter();
    }

    function test_SetRegistryAddress() public {
        string memory key = "TEST_KEY";
        address newAddress = address(0x777);
        
        vm.prank(guardian);
        guardianContract.setRegistryAddress(key, newAddress);
        
        // Verify the address was set
        assertEq(registry.getAddress(key), newAddress);
    }

    function test_SetRegistryAddress_NotGuardian() public {
        vm.prank(address(1));
        vm.expectRevert("!guardian");
        guardianContract.setRegistryAddress("KEY", address(0x777));
    }

    function test_RecoverERC20() public {
        uint256 amount = 1000e18;
        deal(address(stablecoin), address(guardian), amount);
        
        uint256 guardianBalanceBefore = stablecoin.balanceOf(guardian);
        
        vm.prank(guardian);
        guardianContract.recoverERC20(IERC20(address(stablecoin)));
        
        uint256 guardianBalanceAfter = stablecoin.balanceOf(guardian);
        assertEq(guardianBalanceAfter - guardianBalanceBefore, amount);
        assertEq(stablecoin.balanceOf(address(guardianContract)), 0);
    }

    function test_RecoverERC20_NotGuardian() public {
        vm.prank(address(1));
        vm.expectRevert("!guardian");
        guardianContract.recoverERC20(IERC20(address(stablecoin)));
    }

    function test_ViewPermissions() public {
        GuardianUpgradeable.Permissions memory permissions = guardianContract.viewPermissions();
        
        // All permissions should be true based on our setup
        assertTrue(permissions.pauseAllPairs, "pauseAllPairs should be true");
        assertTrue(permissions.cancelProposal, "cancelProposal should be true");
        assertTrue(permissions.updateProposalDescription, "updateProposalDescription should be true");
        assertTrue(permissions.revertVoter, "revertVoter should be true");
        assertTrue(permissions.setRegistryAddress, "setRegistryAddress should be true");
    }

    function test_ViewPermissions_NoPermissions() public {
        // Remove all permissions
        vm.startPrank(address(core));
        core.setOperatorPermissions(
            address(guardianContract),
            address(0),
            IResupplyPair.pause.selector,
            false,
            IAuthHook(address(0))
        );
        core.setOperatorPermissions(
            address(guardianContract),
            address(voter),
            Voter.cancelProposal.selector,
            false,
            IAuthHook(address(0))
        );
        core.setOperatorPermissions(
            address(guardianContract),
            address(voter),
            Voter.updateProposalDescription.selector,
            false,
            IAuthHook(address(0))
        );
        core.setOperatorPermissions(
            address(guardianContract),
            address(core),
            ICore.setVoter.selector,
            false,
            IAuthHook(address(0))
        );
        core.setOperatorPermissions(
            address(guardianContract),
            address(registry),
            IResupplyRegistry.setAddress.selector,
            false,
            IAuthHook(address(0))
        );
        vm.stopPrank();

        GuardianUpgradeable.Permissions memory permissions = guardianContract.viewPermissions();
        
        // All permissions should be false
        assertFalse(permissions.pauseAllPairs, "pauseAllPairs should be false");
        assertFalse(permissions.cancelProposal, "cancelProposal should be false");
        assertFalse(permissions.updateProposalDescription, "updateProposalDescription should be false");
        assertFalse(permissions.revertVoter, "revertVoter should be false");
        assertFalse(permissions.setRegistryAddress, "setRegistryAddress should be false");
    }

    function test_HasPermission() public {
        // Test with permission
        bool hasPermission = guardianContract.hasPermission(address(0), IResupplyPair.pause.selector);
        assertTrue(hasPermission, "Should have permission for pause");

        // Test without permission
        bool noPermission = guardianContract.hasPermission(address(0x999), IResupplyPair.pause.selector);
        assertFalse(noPermission, "Should not have permission for unknown target");
    }

    function test_GetVoter() public {
        // This is an internal function, but we can test it indirectly through cancelProposal
        // Create a proposal first
        Voter.Action[] memory actions = new Voter.Action[](1);
        actions[0] = Voter.Action({
            target: address(pair),
            data: abi.encodeWithSelector(IResupplyPair.pause.selector)
        });
        uint256 proposalId = voter.createNewProposal(
            address(this),
            actions,
            "Test proposal"
        );

        vm.prank(guardian);
        guardianContract.cancelProposal(proposalId);
    }

    function test_Initialize() public {
        // Test that initialize sets the guardian correctly
        assertEq(guardianContract.guardian(), guardian);
    }

    function test_Initialize_AlreadyInitialized() public {
        // Try to initialize again should revert
        vm.expectRevert();
        guardianContract.initialize(address(0x999));
    }

    function test_CoreConstant() public {
        assertEq(address(guardianContract.core()), CORE);
    }

    function test_RegistryConstant() public {
        assertEq(address(guardianContract.registry()), 0x10101010E0C3171D894B71B3400668aF311e7D94);
    }
}