// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Setup } from "../Setup.sol";
import { Guardian } from "src/dao/Guardian.sol";
import { ICore } from "src/interfaces/ICore.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IVoter } from "src/interfaces/IVoter.sol";

contract GuardianTest is Setup {
    Guardian public guardian;

    function setUp() public override {
        super.setUp();
        guardianAddress = address(0x1234);
        guardian = new Guardian(core, registry);
        core.setOperatorPermissions(
            address(guardian), 
            address(0), // can call on any target
            IResupplyPair.pause.selector,
            true,
            address(0) // auth hook
        );

        core.setOperatorPermissions(
            address(guardian), 
            address(voter), // can call on voter
            IVoter.cancelProposal.selector,
            true,
            address(0) // auth hook
        );

        // Set initial guardian address
        guardian.setGuardian(dev);
    }

    function testSetGuardian() public {
        address newGuardian = address(0xDEAD);
        guardian.setGuardian(newGuardian);
        assertEq(guardian.guardian(), newGuardian);
    }

    function testSetGuardianNotOwner() public {
        vm.prank(address(0xBABE));
        vm.expectRevert("!owner");
        guardian.setGuardian(address(0xDEAD));
    }

    function testPausePair() public {
        vm.prank(guardian);
        guardian.pausePair(pair);
        assertTrue(IResupplyPair(pair).paused());
    }

    function testPausePairNotGuardian() public {
        vm.prank(address(0xBABE));
        vm.expectRevert("!guardian");
        guardian.pausePair(pair);
    }

    function testPauseAllPairs() public {
        vm.prank(guardian);
        guardian.pauseAllPairs();
        assertTrue(IResupplyPair(pair).paused());
        assertTrue(IResupplyPair(pair).paused());
    }

    function testPauseAllPairsNotGuardian() public {
        vm.prank(address(0xBABE));
        vm.expectRevert("!guardian");
        guardian.pauseAllPairs();
    }

    function testCancelProposal() public {
        uint256 proposalId = 1;
        vm.prank(guardian);
        guardian.cancelProposal(proposalId);
        assertTrue(IResupplyPair(voter).proposalCancelled(proposalId));
    }

    function testCancelProposalNotGuardian() public {
        vm.prank(address(0xBABE));
        vm.expectRevert("!guardian");
        guardian.cancelProposal(1);
    }
}

// Mock contracts for testing
contract MockCore {
    function execute(address target, bytes memory data) external returns (bool, bytes memory) {
        (bool success, bytes memory result) = target.call(data);
        require(success, "call failed");
        return (success, result);
    }
}

contract MockRegistry is IResupplyRegistry {
    function getAllPairAddresses() external view returns (address[] memory) {
        address[] memory pairs = new address[](2);
        pairs[0] = address(0x1111);
        pairs[1] = address(0x2222);
        return pairs;
    }

    function getAddress(string memory key) external view returns (address) {
        if (keccak256(bytes(key)) == keccak256(bytes("VOTER"))) {
            return address(0x3333);
        }
        return address(0);
    }

    // Implement other required interface functions...
}

contract MockVoter {
    mapping(uint256 => bool) public cancelledProposals;

    function cancelProposal(uint256 proposalId) external {
        cancelledProposals[proposalId] = true;
    }

    function proposalCancelled(uint256 proposalId) external view returns (bool) {
        return cancelledProposals[proposalId];
    }
}

contract MockPair {
    bool public paused;

    function pause() external {
        paused = true;
    }
} 