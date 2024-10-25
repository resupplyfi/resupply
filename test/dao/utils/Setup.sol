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
import { EmissionsController } from "../../../src/dao/emissions/EmissionsController.sol";
import { GovToken } from "../../../src/dao/GovToken.sol";
import { IGovToken } from "../../../src/interfaces/IGovToken.sol";

contract Setup is Test {
    Core public core;
    MockToken public stakingToken;
    IGovStaker public staker;
    GovStakerEscrow public escrow;
    Voter public voter;
    GovToken public govToken;
    EmissionsController public emissionsController;
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
        vm.label(address(govToken), "Gov Token");
        vm.label(address(emissionsController), "Emissions Controller");
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
        govToken = new GovToken(address(core));
        
        uint256 epochsPer = 1;
        emissionsController = new EmissionsController(
            address(core), 
            address(govToken), 
            getEmissionsSchedule(), 
            epochsPer
        );
    }

    function getEmissionsSchedule() public view returns (uint256[] memory) {
        uint256[] memory schedule = new uint256[](5);
        schedule[0] = 2 * 10 ** 16;     // 2%
        schedule[1] = 4 * 10 ** 16;     // 4%
        schedule[2] = 6 * 10 ** 16;     // 6%
        schedule[3] = 8 * 10 ** 16;     // 8%
        schedule[4] = 10 * 10 ** 16;    // 10%
        return schedule;
    }

}