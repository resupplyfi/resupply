pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { GovStaker } from "../../src/dao/staking/GovStaker.sol";
import { GovStakerEscrow } from "../../src/dao/staking/GovStakerEscrow.sol";
import { MockToken } from "../mocks/MockToken.sol";
import { Setup } from "./utils/Setup.sol";
import { MockPair } from "../mocks/MockPair.sol";
import { Voter } from "../../src/dao/Voter.sol";
import { GuardianOperator } from "../../src/dao/operators/GuardianOperator.sol";
import { IAuthHook } from "../../src/interfaces/IAuthHook.sol";
import { GuardianAuthHook } from "../../src/dao/auth/GuardianAuthHook.sol";
import { ICore } from "../../src/interfaces/ICore.sol";

contract GuardianOperatorTest is Setup {
    MockPair pair;
    GuardianOperator guardianOperator;
    address guardianMultisig = address(0x555);
    GuardianAuthHook authHook;
    function setUp() public override {
        super.setUp();

        // Create a mock protocol contract for us to test with
        pair = new MockPair(address(core));

        guardianOperator = new GuardianOperator(address(core), guardianMultisig);
        assertEq(guardianOperator.guardian(), guardianMultisig);
        authHook = new GuardianAuthHook();

        // Transfer ownership of the core contract to the voter contract
        vm.prank(address(core));
        core.transferVoter(address(voter));
        vm.prank(address(voter));
        core.acceptTransferVoter();
        
        // Give user1 some stake so they can create a proposal + vote.
        vm.prank(user1);
        staker.stake(user1, 100e18);
        skip(staker.epochLength() * 2); // We skip 2, so that the stake can be registered (first epoch) and finalized (second epoch).
        
        vm.label(address(guardianOperator), "Guardian Operator");
        vm.label(address(authHook), "Guardian Auth Hook");
    }

    function test_pauseProtocol() public {
        vm.expectRevert("!guardian");
        guardianOperator.pauseProtocol();

        // Setup permissions for guardianOperator to call pauseProtocol on core
        setOperatorPermissionsToPauseProtocol();

        vm.prank(address(guardianMultisig));
        guardianOperator.pauseProtocol();
        assertEq(core.isProtocolPaused(), true);
    }

    function test_UnpauseProtocol() public {
        assertNotEq(address(authHook), address(0));

        // Setup permissions for guardianOperator to call pauseProtocol on core
        setOperatorPermissionsToPauseProtocol();

        (, IAuthHook hook) = core.operatorPermissions(
            address(guardianOperator), 
            address(core),
            bytes4(keccak256("pauseProtocol(bool)"))
        );
        assertEq(address(hook), address(authHook));

        // Pause the protocol
        vm.prank(address(core));
        core.pauseProtocol(true);

        // Attempt to unpause the protocol
        vm.prank(address(guardianMultisig));
        vm.expectRevert("Auth PostHook Failed");
        guardianOperator.execute(
            address(core),
            abi.encodeWithSelector(
                bytes4(keccak256("pauseProtocol(bool)")),
                false // Unpause
            )
        );

        // Protocol should still be paused
        assertEq(core.isProtocolPaused(), true);
    }

    function test_cancelProposal() public {
        uint256 proposalId = voter.getProposalCount();
        vm.expectRevert("!guardian");
        guardianOperator.cancelProposal(proposalId);

        setOperatorPermissionsToCancelProposal();
        uint256 propId = queueDummyProposal();

        vm.prank(address(guardianMultisig));
        guardianOperator.cancelProposal(propId);
        (, , , , , bool processed, bool executable, ) = voter.getProposalData(propId);
        assertEq(processed, true);
    }

    function test_CannotCancelProposalWithCancelerPayload() public {
        setOperatorPermissionsToCancelProposal();
        uint256 propId = queueDummyProposalWithCancelerPayload();
        
        vm.prank(address(guardianMultisig));
        vm.expectRevert("Contains canceler payload");
        guardianOperator.cancelProposal(propId);
        (, , , , , bool processed, bool executable, ) = voter.getProposalData(propId);
        assertEq(processed, false);
    }

    function test_setGuardian() public {
        vm.prank(address(guardianMultisig));
        vm.expectRevert("!core");
        guardianOperator.setGuardian(user1);
        assertEq(guardianOperator.guardian(), guardianMultisig);

        vm.prank(address(core));
        vm.expectEmit(true, false, false, false);
        emit GuardianOperator.GuardianSet(user1);
        guardianOperator.setGuardian(user1);
        assertEq(guardianOperator.guardian(), user1);
    }

    function setOperatorPermissionsToPauseProtocol() public {
        bytes4 selector = bytes4(keccak256("pauseProtocol(bool)"));
        vm.prank(address(core));
        core.setOperatorPermissions(
            address(guardianOperator), // caller
            address(core), // target
            selector,
            true, // authorized
            IAuthHook(address(authHook))
        );

        (bool auth, ) = core.operatorPermissions(
            address(guardianOperator), 
            address(core),
            selector
        );
        assertEq(auth, true);
    }

    function setOperatorPermissionsToCancelProposal() public {
        bytes4 selector = ICore.cancelProposal.selector;
        vm.prank(address(core));
        core.setOperatorPermissions(
            address(guardianOperator), // caller
            address(voter),            // target
            selector,
            true,                      // authorized
            IAuthHook(address(0))
        );

        (bool auth, ) = core.operatorPermissions(
            address(guardianOperator), 
            address(voter),
            selector
        );
        assertEq(auth, true);
    }

    function queueDummyProposal() public returns (uint256) {
        // Simulate a user reaching the minimum weight to create a proposal
        vm.prank(user1);
        staker.stake(user1, 100e18);
        skip(staker.epochLength() * 2);

        // Create a dummy proposal
        Voter.Action[] memory payload = new Voter.Action[](1);
        payload[0] = Voter.Action({
            target: address(pair),
            data: abi.encodeWithSelector(pair.setValue.selector, 5)
        }); 
        vm.prank(user1);
        return voter.createNewProposal(user1, payload);
    }

    function queueDummyProposalWithCancelerPayload() public returns (uint256) {
        // Create a dummy proposal
        Voter.Action[] memory payload = new Voter.Action[](2);
        payload[0] = Voter.Action({
            target: address(core),
            data: abi.encodeWithSelector(
                core.setOperatorPermissions.selector, 
                address(guardianOperator), 
                address(voter), 
                ICore.cancelProposal.selector, 
                true,
                address(0)
            )
        });
        payload[1] = Voter.Action({
            target: address(core),
            data: abi.encodeWithSelector(
                core.setOperatorPermissions.selector, 
                address(guardianOperator), 
                address(voter), 
                ICore.cancelProposal.selector, 
                true,
                address(0)
            )
        });
        vm.prank(user1);
        vm.expectRevert("Payload with canceler must be single action");
        voter.createNewProposal(user1, payload);

        skip(voter.MIN_TIME_BETWEEN_PROPOSALS());

        payload = new Voter.Action[](1);
        payload[0] = Voter.Action({
            target: address(core),
            data: abi.encodeWithSelector(
                core.setOperatorPermissions.selector, 
                address(guardianOperator), 
                address(voter), 
                ICore.cancelProposal.selector, 
                true,
                address(0)
            )
        });
        vm.prank(user1);
        return voter.createNewProposal(user1, payload);
    }
}
