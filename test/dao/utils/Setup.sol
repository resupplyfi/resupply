// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.22;

// import "forge-std/Test.sol";
// import "forge-std/console.sol";
import { Test } from "../../../lib/forge-std/src/Test.sol";
import { console } from "../../../lib/forge-std/src/console.sol";
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
import { VestManager } from "../../../src/dao/tge/VestManager.sol";
import { Treasury } from "../../../src/dao/Treasury.sol";
import { PermaLocker } from "../../../src/dao/tge/PermaLocker.sol";
import { ResupplyRegistry } from "../../../src/protocol/ResupplyRegistry.sol";

contract Setup is Test {
    Core public core;
    GovStaker public staker;
    GovStakerEscrow public escrow;
    Voter public voter;
    GovToken public govToken;
    GovToken public stakingToken;
    EmissionsController public emissionsController;
    VestManager public vestManager;
    ResupplyRegistry public registry;
    address public prismaToken = 0xdA47862a83dac0c112BA89c6abC2159b95afd71C;
    address public user1 = address(0x11);
    address public user2 = address(0x22);
    address public user3 = address(0x33);
    address public dev = address(0x42069);
    address public tempGov = address(987);
    Treasury public treasury;
    PermaLocker public permaLocker1;
    PermaLocker public permaLocker2;

    function setUp() public virtual {

        deployContracts();

        deal(address(govToken), user1, 1_000_000 * 10 ** 18);
        vm.prank(user1);
        govToken.approve(address(staker), type(uint256).max);

        // label all the used addresses for traces
        vm.label(address(tempGov), "Temp Gov");
        vm.label(address(core), "Core");
        vm.label(address(voter), "Voter");
        vm.label(address(govToken), "Gov Token");
        vm.label(address(emissionsController), "Emissions Controller");
        vm.label(address(permaLocker1), "PermaLocker 1");
        vm.label(address(permaLocker2), "PermaLocker 2");
        vm.label(address(staker), "Gov Staker");
        vm.label(address(escrow), "Gov Staker Escrow");
        vm.label(address(treasury), "Treasury");
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
            2       // Bootstrap epochs
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