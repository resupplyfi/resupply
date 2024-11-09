pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Setup } from "../utils/Setup.sol";
import { EmissionsController } from "../../../src/dao/emissions/EmissionsController.sol";
import { GovToken } from "../../../src/dao/GovToken.sol";
import { BasicReceiver } from "../../../src/dao/emissions/receivers/BasicReceiver.sol";

contract EmissionsControllerTest is Setup {

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
            uint256 epoch = emissionsController.getEpoch();
            
            uint256 supply = govToken.totalSupply();
            vm.prank(address(basicReceiver1));
            uint256 amount = emissionsController.fetchEmissions();
            uint256 rate = emissionsController.emissionsRate(); // get the rate that was used at mint
            
            uint256 expected = supply * rate * epochLength / 365 days / 1e18;

            expected = epoch < emissionsController.BOOTSTRAP_EPOCHS() ? 0 : expected; // No emissions during bootstrap

            assertEq(expected, amount);

            skip(epochLength);
            vm.roll(block.number + 1);
            epoch = emissionsController.getEpoch();
        }
    }

    function getExpectedEmissions(uint256 rate, uint256 supply, uint256 epoch) public view returns (uint256) {
        uint256 expected = supply * rate * epochLength / 365 days / 1e18;
        return epoch < emissionsController.BOOTSTRAP_EPOCHS() ? 0 : expected;
    }

    function getEmissionsRate() public view returns (uint256) {
        uint256 rate = emissionsController.emissionsRate();

        uint256 epoch = emissionsController.getEpoch();
        uint256 lastEmissionsUpdate = emissionsController.lastEmissionsUpdate();
        if (epoch - lastEmissionsUpdate >= emissionsController.epochsPer()) {
            rate = emissionsController.getScheduleLength() > 0
                ? emissionsController.getSchedule()[emissionsController.getScheduleLength() - 1]
                : emissionsController.tailRate();
        }
        return rate;
    }

    // TODO: test what happens when a few weeks pass without any receivers connected
    function test_NoReceiversConnected() public {
        uint256 i;
        for (i = 0; i < 2; i++) {
            skip(epochLength);
            console.log("xxx", getEpoch(), emissionsController.emissionsRate());
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
            // console2.log("xxxx", getEmissionsRate(), govToken.totalSupply(), emissionsController.getEpoch());
            // expected *= (emissionsController.getEpoch()+1 - emissionsController.BOOTSTRAP_EPOCHS());
            vm.prank(address(basicReceiver1));
            uint256 amount = emissionsController.fetchEmissions();
            console.log(getEpoch(), emissionsController.emissionsRate());
            if (i != 0) assertEq(expected, amount);
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

    function getEpoch() public view returns (uint256) {
        return emissionsController.getEpoch();
    }
}
