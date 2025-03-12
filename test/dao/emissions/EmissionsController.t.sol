pragma solidity ^0.8.22;

import { console } from "../../../lib/forge-std/src/console.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Setup } from "../../Setup.sol";
import { EmissionsController } from "../../../src/dao/emissions/EmissionsController.sol";
import { GovToken } from "../../../src/dao/GovToken.sol";
import { MockReceiver } from "../../mocks/MockReceiver.sol";

contract EmissionsControllerTest is Setup {

    uint256 public constant DUST = 100;
    MockReceiver public mockReceiver1;
    MockReceiver public mockReceiver2;
    MockReceiver public mockReceiver3;

    function setUp() public override {
        super.setUp();
        vm.startPrank(address(core));
        emissionsController = new EmissionsController(
            address(core), // core
            address(govToken), // govtoken
            getEmissionsSchedule(), // emissions
            52,         // epochs per
            2e16,      // tail rate
            0           // bootstrap epochs
        );
        govToken.setMinter(address(emissionsController));

        mockReceiver1 = new MockReceiver(address(core), address(emissionsController), "Mock Receiver 1");
        mockReceiver2 = new MockReceiver(address(core), address(emissionsController), "Mock Receiver 2");
        mockReceiver3 = new MockReceiver(address(core), address(emissionsController), "Mock Receiver 3");

        vm.stopPrank();
    }

    function test_EmissionsTotalSupplyAfterFiveYears() public { 
        vm.prank(address(core));
        emissionsController.registerReceiver(address(mockReceiver1));

        uint256 startSupply = govToken.globalSupply();
        assertEq(startSupply, 60_000_000e18); // Amount minted at genesis
        uint256 year = 52 weeks;

        for (uint256 i = 0; i < 5; i++) {
            skip(year);
            vm.prank(address(mockReceiver1));
            uint256 amount = emissionsController.fetchEmissions();
            console.log("year %d supply: %d", i+1, govToken.globalSupply()/1e18);
        }

        uint256 expectedSupply = 100_000_000e18;
        assertApproxEqAbs(
            govToken.globalSupply(), 
            expectedSupply, 
            10000e18,  // maximum absolute difference allowed
            "Global supply outside acceptable range"
        );
    }

    function test_DefaultEmissionsSchedule() public {
        assertFalse(emissionsController.isRegisteredReceiver(address(mockReceiver1)));
        vm.prank(address(core));
        emissionsController.registerReceiver(address(mockReceiver1)); // Defaults to 100% weight
        assertTrue(emissionsController.isRegisteredReceiver(address(mockReceiver1)));

        for (uint256 i = 0; i < 10; i++) {
            uint256 expected = getExpectedEmissions(
                emissionsController,
                getEmissionsRate(), 
                govToken.totalSupply(), 
                getEpoch()
            );

            vm.prank(address(mockReceiver1));
            uint256 amount = emissionsController.fetchEmissions();
            assertEq(expected, amount);

            skip(epochLength);
        }
    }

    function test_UpdateScheduleBeforeReceiversAreRegisteredDoesNotMint() public {
        uint256 startSupply = govToken.totalSupply();
        uint256[] memory rates = new uint256[](2);
        rates[0] = 100;
        rates[1] = 101;
        uint256 epochsPer = 1;
        uint256 tailRate = 98;

        // Make sure emissions cannot mint without receivers
        skip(epochLength*5);
        vm.prank(address(core));
        emissionsController.setEmissionsSchedule(rates, epochsPer, tailRate);
        assertEq(govToken.totalSupply(), startSupply);

        // Ensure all new mints go to first receiver, and none go to unallocated
        vm.prank(address(core));
        emissionsController.registerReceiver(address(mockReceiver1));
        vm.prank(address(mockReceiver1));
        emissionsController.fetchEmissions();
        assertGt(govToken.totalSupply(), startSupply);
        assertEq(emissionsController.unallocated(), 0);
    }

    function test_AddMultipleReceiversAndWeights() public {
        uint256[] memory receiverIds = new uint256[](3);
        receiverIds[0] = 0;
        receiverIds[1] = 1;
        receiverIds[2] = 2;
        uint256[] memory weights = new uint256[](3);
        weights[0] = 2_000;
        weights[1] = 3_500;
        weights[2] = 4_500;

        vm.prank(address(core));
        emissionsController.registerReceiver(address(mockReceiver1));
        uint256 amount;

        for (uint256 i = 0; i < emissionsController.nextReceiverId(); i++) {
            (bool active, address receiver, uint256 weight) = emissionsController.idToReceiver(i);
            vm.prank(receiver);
            uint256 amount = emissionsController.fetchEmissions();
        }

        skip(epochLength); // enter epoch 1

        vm.prank(address(core));
        emissionsController.registerReceiver(address(mockReceiver2));
        for (uint256 i = 0; i < emissionsController.nextReceiverId(); i++) {
            (bool active, address receiver, uint256 weight) = emissionsController.idToReceiver(i);
            vm.prank(receiver);
            uint256 amount = emissionsController.fetchEmissions();
        }

        skip(epochLength); // enter epoch 2

        vm.prank(address(core));
        emissionsController.registerReceiver(address(mockReceiver3));
        weights[0] = 2_001; // Exceeds 100% by 1 BPS
        vm.expectRevert("Total weight must be 100%");
        setNewWeights(receiverIds, weights);
        
        weights[0] = 2_000; // Fix weight so the aggregate is now 100% even
        setNewWeights(receiverIds, weights);
        
        checkTotalAllocatedMatchesECBalance();

        skip(epochLength); // enter epoch 3
        weights[0] = 1_000;
        weights[1] = 3_000;
        weights[2] = 6_000;
        setNewWeights(receiverIds, weights);

        skip(epochLength); // enter epoch 4

        checkTotalAllocatedMatchesECBalance();

        skip(epochLength); // enter epoch 5

        uint256[] memory receiverIds2 = new uint256[](2);
        receiverIds2[0] = 1;
        receiverIds2[1] = 2;
        uint256[] memory weights2 = new uint256[](2);
        weights2[0] = 5_500;
        weights2[1] = 3_500;
        setNewWeights(receiverIds2, weights2);
        
        checkTotalAllocatedMatchesECBalance();

        skip(epochLength); // enter epoch 6

        checkTotalAllocatedMatchesECBalance();
    }

    function setNewWeights(uint256[] memory receiverIds, uint256[] memory weights) internal {
        vm.prank(address(core));
        emissionsController.setReceiverWeights(
            receiverIds,
            weights
        );
    }


    function test_NoReceiversConnected() public {
        uint256 i;
        for (i = 0; i < emissionsController.BOOTSTRAP_EPOCHS() + 2; i++) {
            skip(epochLength);
        }

        vm.prank(address(core));
        emissionsController.registerReceiver(address(mockReceiver1));
        assertEq(emissionsController.nextReceiverId(), 1);

        for (i = 0; i < 20; i++) {
            skip(epochLength);
            assertEq(emissionsController.nextReceiverId(), 1);
            uint256 expected = getExpectedEmissions(
                emissionsController,
                getEmissionsRate(), 
                govToken.totalSupply(),
                getEpoch()
            );
            
            vm.prank(address(mockReceiver1));
            uint256 amount = emissionsController.fetchEmissions();
            if (i != 0) assertEq(expected, amount);
            else assertGt(amount, expected); // First iteration will mint multiple epochs worth
        }

    }

    function test_PreventDuplicateReceiver() public {
        vm.startPrank(address(core));
        emissionsController.registerReceiver(address(mockReceiver1));
        vm.expectRevert("Receiver already added.");
        emissionsController.registerReceiver(address(mockReceiver1));
        emissionsController.registerReceiver(address(mockReceiver2));
        vm.expectRevert("Receiver already added.");
        emissionsController.registerReceiver(address(mockReceiver1));
        vm.expectRevert("Receiver already added.");
        emissionsController.registerReceiver(address(mockReceiver2));
    }

    function test_RecoverUnallocated() public {
        vm.startPrank(address(core));
        emissionsController.registerReceiver(address(mockReceiver1));
        uint256 id = emissionsController.receiverToId(address(mockReceiver1));
        emissionsController.deactivateReceiver(id); // By deactivating only receiver, all emissions are pushed to unallocated
        // Skip thru some epochs to build rewards
        for (uint256 i = 0; i < 10; i++) {
            skip(epochLength);
            vm.roll(block.number + 1);
        }

        uint alloc = mockReceiver1.allocateEmissions(); // triggers ec.fetchEmissions()
        (bool active, ,) = emissionsController.idToReceiver(id);
        govToken.balanceOf(address(mockReceiver1));
        if (!active) assertEq(alloc, 0);
        else assertGt(alloc, 0);
        // Verify we can recover unallocated
        uint256 unallocated = emissionsController.unallocated();
        assertGt(unallocated, 0);
        
        uint coreBalance = govToken.balanceOf(address(core));
        emissionsController.recoverUnallocated(address(core));
        assertEq(emissionsController.unallocated(), 0);
        assertGt(govToken.balanceOf(address(core)), coreBalance);
        vm.stopPrank();
    }

    function test_ChangeEmissionsSchedule() public {
        vm.startPrank(address(core));

        uint256[] memory rates = new uint256[](0);
        uint256 epochsPer = 0;
        uint256 tailRate = 0;

        // Schedule cannot be empty
        vm.expectRevert("Must be >0");
        emissionsController.setEmissionsSchedule(rates, epochsPer, tailRate);

        rates = new uint256[](2);
        rates[0] = 100;
        rates[1] = 99;

        // Epochs per must be greater than 0
        vm.expectRevert("Must be >0");
        emissionsController.setEmissionsSchedule(rates, epochsPer, tailRate);
        epochsPer = 1;

        // Rates must be in decaying order
        vm.expectRevert("Rate greater than predecessor");
        emissionsController.setEmissionsSchedule(rates, epochsPer, tailRate);

        // Final rate can't be less than tail rate
        rates[0] = 99;
        rates[1] = 101;
        tailRate = 100;
        vm.expectRevert("Final rate less than tail rate");
        emissionsController.setEmissionsSchedule(rates, epochsPer, tailRate);

        // Final rate may be equal to tail rate
        rates[0] = 100;
        rates[1] = 101;
        tailRate = 100;
        emissionsController.setEmissionsSchedule(rates, epochsPer, tailRate);

        vm.stopPrank();
    }

    function test_EmissionsChangesAndTailRate() public {
        vm.startPrank(address(core));
        emissionsController.registerReceiver(address(mockReceiver1));

        uint256[] memory rates = new uint256[](2);
        rates[0] = 99;
        rates[1] = 100;
        uint256 epochsPer = 1;
        uint256 tailRate = 98;
        
        emissionsController.setEmissionsSchedule(rates, epochsPer, tailRate);
        vm.stopPrank();
        uint256 startEpoch = getEpoch();
        uint256 epochsUntilTail = rates.length * epochsPer;
        for (uint256 i = 0; i < 100; i++) {
            skip(epochLength);
            vm.prank(address(mockReceiver1));
            emissionsController.fetchEmissions();
            // if schedule is exhausted, assert that tail rate is active
            if (getEpoch() - (startEpoch + 1) >= epochsUntilTail) {
                assertEq(emissionsController.emissionsRate(), tailRate);
            }
            else {
                assertGt(emissionsController.emissionsRate(), tailRate);
            }
        }
    }

    function test_AddMultipleReceivers() public {
        vm.startPrank(address(core));
        emissionsController.registerReceiver(address(mockReceiver1));
        emissionsController.registerReceiver(address(mockReceiver2));
        emissionsController.registerReceiver(address(mockReceiver3));
        uint256 nextId = emissionsController.nextReceiverId();
        assertGe(nextId, 3);
        for (uint256 i = 0; i < nextId; i++) {
            (bool active, address receiver, uint256 weight) = emissionsController.idToReceiver(i);
            assertEq(active, true);
        }
    }

    function test_ActivateDeactivateReceiver() public {
        vm.startPrank(address(core));
        emissionsController.registerReceiver(address(mockReceiver1));
        uint256 id = emissionsController.receiverToId(address(mockReceiver1));
        emissionsController.deactivateReceiver(id);
        vm.expectRevert("Receiver not active");
        emissionsController.deactivateReceiver(id);
        vm.expectRevert("Receiver not found");
        emissionsController.deactivateReceiver(69);

        emissionsController.activateReceiver(id);
        vm.expectRevert("Receiver active");
        emissionsController.activateReceiver(id);
        vm.expectRevert("Receiver not found");
        emissionsController.activateReceiver(69);
        vm.stopPrank();
    }

    function checkTotalAllocatedMatchesECBalance() internal {
        uint256 totalAmount;
        uint200 allocatedBefore;
        uint200 allocatedAfter;
        for (uint256 i = 0; i < emissionsController.nextReceiverId(); i++) {
            (bool active, address receiver, uint256 weight) = emissionsController.idToReceiver(i);
            (, allocatedBefore) = emissionsController.allocated(receiver);
            vm.prank(receiver);
            uint256 amount = emissionsController.fetchEmissions();
            (, allocatedAfter) = emissionsController.allocated(receiver);
            totalAmount += allocatedAfter;
        }
        assertApproxEqAbs(totalAmount, govToken.balanceOf(address(emissionsController)), DUST);
    }

    function getExpectedEmissions(EmissionsController ec, uint256 rate, uint256 supply, uint256 epoch) public view returns (uint256) {
        uint256 expected = supply * rate * epochLength / 365 days / 1e18;
        return epoch <= ec.BOOTSTRAP_EPOCHS() ? 0 : expected;
    }

    function getEmissionsRate() public view returns (uint256) {
        uint256 rate = emissionsController.emissionsRate();
        uint256 epoch = emissionsController.getEpoch();
        uint256 lastEmissionsUpdate = emissionsController.lastEmissionsUpdate();
        if (lastEmissionsUpdate > epoch) return rate;
        if (epoch - lastEmissionsUpdate >= emissionsController.epochsPer()) {
            rate = emissionsController.getScheduleLength() > 0
                ? emissionsController.getSchedule()[emissionsController.getScheduleLength() - 1]
                : emissionsController.tailRate();
        }
        return rate;
    }

    function getEpoch() public view returns (uint256) {
        return emissionsController.getEpoch();
    }
}
