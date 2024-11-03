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
import { Vesting } from "../../../src/dao/tge/Vesting.sol";
import { VestManager } from "../../../src/dao/tge/VestManager.sol";
import { Treasury } from "../../../src/dao/Treasury.sol";
import { SubDao } from "../../../src/dao/tge/SubDao.sol";

contract Setup is Test {
    Core public core;
    MockToken public stakingToken;
    IGovStaker public staker;
    GovStakerEscrow public escrow;
    Voter public voter;
    GovToken public govToken;
    EmissionsController public emissionsController;
    Vesting public vesting;
    VestManager public vestManager;
    address public prismaToken = 0xdA47862a83dac0c112BA89c6abC2159b95afd71C;
    address public user1 = address(0x11);
    address public user2 = address(0x22);
    address public user3 = address(0x33);
    address public dev = address(0x42069);
    address public tempGov = address(987);
    Treasury public treasury;
    SubDao public subdao1;
    SubDao public subdao2;

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
        vm.label(address(subdao1), "SubDAO 1");
        vm.label(address(subdao2), "SubDAO 2");
        vm.label(address(staker), "Gov Staker");
        vm.label(address(escrow), "Gov Staker Escrow");
        vm.label(address(treasury), "Treasury");
    }

    function deployContracts() public {
        core = Core(
            address(
                new Core(tempGov, 1 weeks)
            )
        );
        staker = IGovStaker(
            address(
                new GovStaker(
                    address(core), 
                    address(stakingToken), 
                    2
                )
            )
        );

        voter = new Voter(address(core), IGovStaker(staker), 100, 3000);
        address govTokenAddress = computeCreateAddress(address(this), vm.getNonce(address(this))+1);
        vesting = new Vesting(address(core), govTokenAddress, 365 days);
        govToken = new GovToken(
            address(core), 
            address(vesting),
            "Resupply", 
            "RSUP"
        );

        assertEq(address(govToken), govTokenAddress);

        uint256 epochsPer = 10;
        emissionsController = new EmissionsController(
            address(core), 
            address(govToken), 
            getEmissionsSchedule(), 
            epochsPer,
            2 // Bootstrap epochs
        );

        treasury = new Treasury(address(core));
        subdao1 = new SubDao(address(core), user1, address(staker), "Yearn");
        subdao2 = new SubDao(address(core), user2, address(staker), "Convex");
        assertEq(subdao1.owner(), user1);
        assertEq(subdao2.owner(), user2);
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