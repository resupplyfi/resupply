pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Setup } from "../utils/Setup.sol";
import { EmissionsController } from "../../../src/dao/emissions/EmissionsController.sol";
import { GovToken } from "../../../src/dao/GovToken.sol";
import { BasicReceiver } from "../../../src/dao/emissions/receivers/BasicReceiver.sol";

contract EmissionsControllerTest is Setup {

    uint256 public constant DUST = 100;
    uint256 public epochLength;
    BasicReceiver public basicReceiver1;
    BasicReceiver public basicReceiver2;
    BasicReceiver public basicReceiver3;

    function setUp() public override {
        super.setUp();
        vm.startPrank(address(core));
        govToken.setMinter(address(emissionsController));
        epochLength = emissionsController.epochLength();

        basicReceiver1 = new BasicReceiver(address(core), address(emissionsController), "Basic Receiver 1");
        basicReceiver2 = new BasicReceiver(address(core), address(emissionsController), "Basic Receiver 2");
        basicReceiver3 = new BasicReceiver(address(core), address(emissionsController), "Basic Receiver 3");

        vm.stopPrank();
    }

    function test_DefaultEmissionsSchedule() public {
        vm.prank(address(core));
        emissionsController.registerReceiver(address(basicReceiver1)); // Defaults to 100% weight

        for (uint256 i = 0; i < 10; i++) {
            uint256 expected = getExpectedEmissions(
                getEmissionsRate(), 
                govToken.totalSupply(), 
                getEpoch()
            );

            vm.prank(address(basicReceiver1));
            uint256 amount = emissionsController.fetchEmissions();
            assertEq(expected, amount);

            skip(epochLength);
        }
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
        emissionsController.registerReceiver(address(basicReceiver1));
        uint256 amount;

        for (uint256 i = 0; i < emissionsController.nextReceiverId(); i++) {
            (bool active, address receiver, uint256 weight) = emissionsController.idToReceiver(i);
            vm.prank(receiver);
            uint256 amount = emissionsController.fetchEmissions();
            console.log(BasicReceiver(receiver).name(), getEpoch(), weight, amount);
        }

        skip(epochLength);

        vm.prank(address(core));
        emissionsController.registerReceiver(address(basicReceiver2));
        for (uint256 i = 0; i < emissionsController.nextReceiverId(); i++) {
            (bool active, address receiver, uint256 weight) = emissionsController.idToReceiver(i);
            vm.prank(receiver);
            uint256 amount = emissionsController.fetchEmissions();
            console.log(BasicReceiver(receiver).name(), getEpoch(), weight, amount);
        }

        skip(epochLength);

        vm.prank(address(core));
        emissionsController.registerReceiver(address(basicReceiver3));

        weights[0] = 2_001; // Exceeds 100% by 1 BPS
        vm.startPrank(address(core));
        vm.expectRevert("Total weight must be 100%");
        emissionsController.setReceiverWeights(
            receiverIds, 
            weights
        );
        weights[0] = 2_000;
        emissionsController.setReceiverWeights(
            receiverIds,
            weights
        );
        vm.stopPrank();

        
        uint256 totalAmount;
        for (uint256 i = 0; i < emissionsController.nextReceiverId(); i++) {
            (bool active, address receiver, uint256 weight) = emissionsController.idToReceiver(i);
            vm.prank(receiver);
            uint256 amount = emissionsController.fetchEmissions();
            (, uint200 allocated) = emissionsController.allocated(receiver);
            amount = uint256(allocated);
            totalAmount += amount;
            console.log(receiver, getEpoch(), weight, amount);
        }
        assertEq(totalAmount, govToken.balanceOf(address(emissionsController)));

        skip(epochLength);
        weights[0] = 1_000;
        weights[1] = 3_000;
        weights[2] = 6_000;
        vm.prank(address(core));
        emissionsController.setReceiverWeights(
            receiverIds,
            weights
        );
        skip(epochLength);
        totalAmount = 0;
        for (uint256 i = 0; i < emissionsController.nextReceiverId(); i++) {
            (bool active, address receiver, uint256 weight) = emissionsController.idToReceiver(i);
            vm.prank(receiver);
            uint256 amount = emissionsController.fetchEmissions();
            (, uint200 allocated) = emissionsController.allocated(receiver);
            amount = uint256(allocated);
            totalAmount += amount;
            console.log(receiver, getEpoch(), weight, amount);
        }
        assertApproxEqAbs(totalAmount, govToken.balanceOf(address(emissionsController)), DUST);
    }

    

    function test_NoReceiversConnected() public {
        uint256 i;
        for (i = 0; i < emissionsController.BOOTSTRAP_EPOCHS() + 2; i++) {
            skip(epochLength);
        }

        vm.prank(address(core));
        emissionsController.registerReceiver(address(basicReceiver1));
        assertEq(emissionsController.nextReceiverId(), 1);

        for (i = 0; i < 20; i++) {
            skip(epochLength);
            assertEq(emissionsController.nextReceiverId(), 1);
            uint256 expected = getExpectedEmissions(
                getEmissionsRate(), 
                govToken.totalSupply(),
                getEpoch()
            );
            
            vm.prank(address(basicReceiver1));
            uint256 amount = emissionsController.fetchEmissions();
            console.log(getEpoch(), emissionsController.emissionsRate());
            if (i != 0) assertEq(expected, amount);
            else assertGt(amount, expected); // First iteration will mint multiple epochs worth
        }

    }

    function test_PreventDuplicateReceiver() public {
        vm.startPrank(address(core));
        emissionsController.registerReceiver(address(basicReceiver1));
        vm.expectRevert("Receiver already added.");
        emissionsController.registerReceiver(address(basicReceiver1));
        emissionsController.registerReceiver(address(basicReceiver2));
        vm.expectRevert("Receiver already added.");
        emissionsController.registerReceiver(address(basicReceiver1));
        vm.expectRevert("Receiver already added.");
        emissionsController.registerReceiver(address(basicReceiver2));
    }

    function test_RecoverUnallocated() public {
        vm.startPrank(address(core));
        emissionsController.registerReceiver(address(basicReceiver1));
        uint256 id = emissionsController.receiverToId(address(basicReceiver1));
        emissionsController.deactivateReceiver(id); // By deactivating only receiver, all emissions are pushed to unallocated
        // Skip thru some epochs to build rewards
        for (uint256 i = 0; i < 10; i++) {
            skip(epochLength);
            vm.roll(block.number + 1);
        }

        uint alloc = basicReceiver1.allocateEmissions(); // triggers ec.fetchEmissions()
        (bool active, ,) = emissionsController.idToReceiver(id);
        govToken.balanceOf(address(basicReceiver1));
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

    }

    function test_EmissionsChangesAndTailRate() public {

    }

    function test_MultipleReceivers() public {
        vm.startPrank(address(core));
        emissionsController.registerReceiver(address(basicReceiver1));
        emissionsController.registerReceiver(address(basicReceiver2));
        emissionsController.registerReceiver(address(basicReceiver3));
        uint256 nextId = emissionsController.nextReceiverId();
        assertEq(nextId, 3);
        for (uint256 i = 0; i < nextId; i++) {
            (bool active, address receiver, uint256 weight) = emissionsController.idToReceiver(i);
            assertEq(active, true);
            assertEq(receiver, address(i == 0 ? basicReceiver1 : i == 1 ? basicReceiver2 : basicReceiver3));
            assertEq(weight, i==0 ? 10_000 : 0);
        }
    }

    function getExpectedEmissions(uint256 rate, uint256 supply, uint256 epoch) public view returns (uint256) {
        uint256 expected = supply * rate * epochLength / 365 days / 1e18;
        return epoch <= emissionsController.BOOTSTRAP_EPOCHS() ? 0 : expected;
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
