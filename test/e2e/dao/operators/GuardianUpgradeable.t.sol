// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

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
import { ISwapperOdos } from "src/interfaces/ISwapperOdos.sol";
import { IBorrowLimitController } from "src/interfaces/IBorrowLimitController.sol";
import { IInsurancePool } from "src/interfaces/IInsurancePool.sol";

contract GuardianUpgradeableTest is Setup, BaseUpgradeableOperatorTest {
    address public guardian = Protocol.DEPLOYER;
    GuardianUpgradeable public guardianContract;
    IResupplyPair public pair;
    address[] public pairs;

    event GuardianSet(address indexed newGuardian);
    event PairPaused(address indexed pair);
    event GuardedRegistryKeySet(string key, bool indexed guarded);

    function setUp() public override {
        super.setUp();
        deployProxyAndImplementation();
        guardianContract = GuardianUpgradeable(proxy);
        setupPermissions();
        pairs = registry.getAllPairAddresses();
        pair = IResupplyPair(pairs[0]);
        stakeGovToken(1000e18);
        skip(epochLength);

        // Because the guardian contract has a hardcoded registry address which does not
        // match the one in the setup, we need to mock the getAddress calls
        vm.mockCall(
            address(Protocol.REGISTRY),
            abi.encodeWithSelector(IResupplyRegistry.getAddress.selector, "VOTER"),
            abi.encode(address(voter))
        );
        vm.mockCall(
            address(Protocol.REGISTRY),
            abi.encodeWithSelector(IResupplyRegistry.getAddress.selector, "SWAPPER_ODOS"),
            abi.encode(address(odosSwapper))
        );
        vm.mockCall(
            address(Protocol.REGISTRY),
            abi.encodeWithSelector(IResupplyRegistry.getAddress.selector, "INSURANCE_POOL"),
            abi.encode(address(insurancePool))
        );
        vm.mockCall(
            address(Protocol.REGISTRY),
            abi.encodeWithSelector(IResupplyRegistry.getAddress.selector, "BORROW_LIMIT_CONTROLLER"),
            abi.encode(address(borrowLimitController))
        );
        vm.mockCall(
            address(Protocol.REGISTRY),
            abi.encodeWithSelector(IResupplyRegistry.getAllPairAddresses.selector),
            abi.encode(registry.getAllPairAddresses())
        );
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
        setOperatorPermission(address(guardianContract), address(registry), IResupplyRegistry.setAddress.selector, true);
        setOperatorPermission(address(guardianContract), address(0), ISwapperOdos.revokeApprovals.selector, true);
        setOperatorPermission(address(guardianContract), address(0), IBorrowLimitController.cancelRamp.selector, true);
        setOperatorPermission(address(guardianContract), address(0), IInsurancePool.setWithdrawTimers.selector, true);
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
        vm.prank(address(core));
        vm.expectEmit(true, false, false, true);
        emit GuardianSet(newGuardian);
        guardianContract.setGuardian(newGuardian);
        assertEq(guardianContract.guardian(), newGuardian);
    }

    function test_PauseAllPairs() public {
        vm.prank(guardian);
        guardianContract.pauseAllPairs();

        for (uint256 i = 0; i < pairs.length; i++) {
            assertEq(IResupplyPair(pairs[i]).borrowLimit(), 0);
        }
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

    function test_PauseIPWithdrawals() public {
        assertNotEq(IInsurancePool(address(insurancePool)).withdrawTimeLimit(), 0);
        vm.prank(guardian);
        guardianContract.pauseIPWithdrawals();
        assertEq(IInsurancePool(address(insurancePool)).withdrawTimeLimit(), 0, "withdrawTimeLimit not set to 0");
    }

    function test_CancelRamp() public {
        address _pair = pairs[0];
        vm.prank(address(core));
        pair.setBorrowLimit(1); // cannot ramp from 0

        // create a ramp
        vm.prank(address(core));
        borrowLimitController.setPairBorrowLimitRamp(_pair, 100_000e18, block.timestamp + 7 days);

        // partially ramp up from 0
        skip(1 days);
        borrowLimitController.updatePairBorrowLimit(_pair);
        uint256 borrowLimit = pair.borrowLimit();
        assertNotEq(borrowLimit, 0);

        vm.prank(guardian);
        guardianContract.cancelRamp(_pair);
        IBorrowLimitController.PairBorrowLimit memory limitInfo = IBorrowLimitController(address(borrowLimitController)).pairLimits(_pair);
        assertEq(limitInfo.targetBorrowLimit, 0, "targetBorrowLimit not set to 0");
        assertEq(limitInfo.prevBorrowLimit, 0, "prevBorrowLimit not set to 0");
        assertEq(limitInfo.startTime, 0, "startTime not set to 0");
        assertEq(limitInfo.endTime, 0, "endTime not set to 0");
    }

    function test_RecoverERC20() public {
        uint256 amount = 1000e18;
        deal(address(stablecoin), address(guardianContract), amount);
        
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
        // assertTrue(permissions.setRegistryAddress, "setRegistryAddress should be true");
        assertTrue(permissions.revokeSwapperApprovals, "revokeSwapperApprovals should be true");
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
            address(0),
            Voter.cancelProposal.selector,
            false,
            IAuthHook(address(0))
        );
        core.setOperatorPermissions(
            address(guardianContract),
            address(0),
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
        core.setOperatorPermissions(
            address(guardianContract),
            address(0),
            ISwapperOdos.revokeApprovals.selector,
            false,
            IAuthHook(address(0))
        );
        vm.stopPrank();

        GuardianUpgradeable.Permissions memory permissions = guardianContract.viewPermissions();
        
        // All permissions should be false
        assertFalse(permissions.pauseAllPairs, "pauseAllPairs should be false");
        assertFalse(permissions.cancelProposal, "cancelProposal should be false");
        assertFalse(permissions.updateProposalDescription, "updateProposalDescription should be false");
        assertFalse(permissions.setRegistryAddress, "setRegistryAddress should be false");
        assertFalse(permissions.revokeSwapperApprovals, "revokeSwapperApprovals should be false");
    }

    function test_HasPermission() public {
        // Test with permission
        bool hasPermission = guardianContract.hasPermission(address(0), IResupplyPair.pause.selector);
        assertTrue(hasPermission, "Should have permission for pause");

        // Should be true since it's wildcarded
        hasPermission = guardianContract.hasPermission(address(0x999), IResupplyPair.pause.selector);
        assertTrue(hasPermission, "Should have permission for wildcarded target");

        // Should be false
        hasPermission = guardianContract.hasPermission(address(0x999), IResupplyRegistry.setAddress.selector);
        assertFalse(hasPermission, "Should not have permission for unknown target");  
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

    function test_RevokeSwapperApprovals() public {
        vm.prank(guardian);
        guardianContract.revokeSwapperApprovals();
    }

    function test_RevokeSwapperApprovals_NotGuardian() public {
        vm.prank(address(1));
        vm.expectRevert("!guardian");
        guardianContract.revokeSwapperApprovals();
    }

    function test_SetGuardedRegistryKey() public {
        string memory key = "TEST";
        
        vm.prank(address(core));
        vm.expectEmit(true, false, false, true);
        emit GuardedRegistryKeySet(key, true);
        guardianContract.setGuardedRegistryKey(key, true);
        
        assertTrue(guardianContract.guardedRegistryKeys(key));

        vm.prank(guardian);
        vm.expectRevert("Key is guarded");
        guardianContract.setRegistryAddress(key, address(0x0));
    }

    function test_SetGuardedRegistryKey_NotOwner() public {
        string memory key = "TEST_KEY";
        
        vm.prank(guardian);
        vm.expectRevert("!owner");
        guardianContract.setGuardedRegistryKey(key, true);
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