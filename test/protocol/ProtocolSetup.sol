// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.22;

import { Test } from "../../../lib/forge-std/src/Test.sol";
import { console } from "../../../lib/forge-std/src/console.sol";
import { IERC20, SafeERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import { Core } from "../../../src/dao/Core.sol";

contract Setup is Test {
    Core public core;
    

    function setUp() public virtual {

        deployContracts();

        deal(address(govToken), user1, 1_000_000 * 10 ** 18);
        vm.prank(user1);
        govToken.approve(address(staker), type(uint256).max);

        // label all the used addresses for traces
        vm.label(address(tempGov), "Temp Gov");
        vm.label(address(core), "Core");
    }

    function deployContracts() public {
        address[3] memory redemptionTokens;
        redemptionTokens[0] = address(new MockToken('PRISMA', 'PRISMA'));
        redemptionTokens[1] = address(new MockToken('yPRISMA', 'yPRISMA'));
        redemptionTokens[2] = address(new MockToken('cvxPRISMA', 'cvxPRISMA'));

        core = new Core(tempGov, 1 weeks);
        address vestManagerAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this))+2);
        govToken = new GovToken(
            address(core), 
            vestManagerAddress,
            "Resupply", 
            "RSUP"
        );
        staker = new GovStaker(address(core), address(govToken), 2);
        vestManager = new VestManager(
            address(core), 
            address(govToken),
            address(0xdead),   // Burn address
            redemptionTokens,  // Redemption tokens
            365 days           // Time until deadline
        );
        assertEq(address(vestManager), vestManagerAddress);
        
        voter = new Voter(address(core), IGovStaker(address(staker)), 100, 3000);
        stakingToken = govToken;
        
        emissionsController = new EmissionsController(
            address(core), 
            address(govToken), 
            getEmissionsSchedule(), 
            3,      // epochs per
            2e16,   // tail rate
            0       // Bootstrap epochs
        );

        treasury = new Treasury(address(core));
        registry = new ResupplyRegistry(address(core), address(govToken));
        permaLocker1 = new PermaLocker(address(core), user1, address(staker), address(registry), "Yearn");
        permaLocker2 = new PermaLocker(address(core), user2, address(staker), address(registry), "Convex");
        assertEq(permaLocker1.owner(), user1);
        assertEq(permaLocker2.owner(), user2);
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