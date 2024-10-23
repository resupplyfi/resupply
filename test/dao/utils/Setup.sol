// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import { IERC20, SafeERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import { IGovStaker } from "../../../src/interfaces/IGovStaker.sol";
import { GovStaker } from "../../../src/dao/staking/GovStaker.sol";
import { Core } from "../../../src/dao/Core.sol";
import { Voter } from "../../../src/dao/Voter.sol";
import { MockToken } from "../../mocks/MockToken.sol";
import { GovStakerEscrow } from "../../../src/dao/staking/GovStakerEscrow.sol";
import { IGovStakerEscrow } from "../../../src/interfaces/IGovStakerEscrow.sol";

contract Setup is Test {
    Core public core;
    MockToken public stakingToken;
    IGovStaker public staker;
    GovStakerEscrow public escrow;
    Voter public voter;
    address user1 = address(0x11);
    address user2 = address(0x22);
    address user3 = address(0x33);
    address dev = address(0x42069);
    address tempGov = address(987);

    function setUp() public virtual {
        // Deploy the mock factory first for deterministic location
        stakingToken = new MockToken("GovToken", "GOV");

        deployContracts();

        vm.startPrank(user1);
        stakingToken.approve(address(staker), type(uint256).max);
        stakingToken.mint(user1, 1_000_000 * 10 ** 18);
        vm.stopPrank();

        // label all the used addresses for traces
        vm.label(address(stakingToken), "Gov Token");
        vm.label(address(tempGov), "Temp Gov");
        vm.label(address(core), "Core");
        vm.label(address(voter), "Voter");
    }

    function deployContracts() public {
        core = Core(
            address(
                new Core(tempGov, 1 weeks)
            )
        );
        uint256 nonce = vm.getNonce(address(this));
        address escrowAddress = computeCreateAddress(address(this), nonce);
        address govStakingAddress = computeCreateAddress(address(this), nonce + 1);
        escrow = new GovStakerEscrow(
            govStakingAddress, address(stakingToken)
        );

        staker = IGovStaker(
            address(
                new GovStaker(
                    address(core), 
                    address(stakingToken), 
                    IGovStakerEscrow(escrowAddress), 
                    2
                )
            )
        );

        voter = new Voter(address(core), IGovStaker(staker), 100, 3000);
    }

}