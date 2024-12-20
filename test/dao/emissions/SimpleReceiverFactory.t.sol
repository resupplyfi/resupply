pragma solidity ^0.8.22;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Setup } from "test/Setup.sol";
import { SimpleReceiverFactory } from "src/dao/emissions/receivers/SimpleReceiverFactory.sol";
import { SimpleReceiver } from "src/dao/emissions/receivers/SimpleReceiver.sol";
import { GovToken } from "src/dao/GovToken.sol";
import { EmissionsController } from "src/dao/emissions/EmissionsController.sol";
import { Errors } from "@openzeppelin/contracts/utils/Errors.sol";

contract SimpleReceiverFactoryTest is Setup {

    address public simpleReceiverImplementation;
    SimpleReceiverFactory public simpleReceiverFactory;

    function setUp() public override {
        super.setUp();
        vm.startPrank(address(core));
        emissionsController = new EmissionsController(
            address(core), // core
            address(govToken), // govtoken
            getEmissionsSchedule(), // emissions
            1, // epochs per
            0, // tail rate
            0 // bootstrap epochs
        );
        govToken.setMinter(address(emissionsController));
        vm.stopPrank();
        simpleReceiverImplementation = address(new 
            SimpleReceiver(
                address(core), 
                address(emissionsController)
            )
        );

        simpleReceiverFactory = new SimpleReceiverFactory(
            address(core), 
            address(emissionsController), 
            simpleReceiverImplementation
        );
        vm.prank(address(core));
        govToken.setMinter(address(emissionsController));
    }

    function test_ReceiverLookupByAddress() public {
        address predictedReceiverAddress = simpleReceiverFactory.getDeterministicAddress("Test Receiver");
        vm.prank(address(core));
        address receiver = simpleReceiverFactory.deployNewReceiver("Test Receiver", new address[](0));
        assertEq(receiver, predictedReceiverAddress);
        address receiverByName = simpleReceiverFactory.getReceiverByName("Test Receiver");
        assertEq(receiverByName, receiver);
    }

    function test_MultipleReceiversWithSameName() public {
        vm.startPrank(address(core));
        address receiver = simpleReceiverFactory.deployNewReceiver("Test Receiver", new address[](0));
        
        address receiver2;
        vm.expectRevert(Errors.FailedDeployment.selector);
        receiver2 = simpleReceiverFactory.deployNewReceiver("Test Receiver", new address[](0));
        
        address simpleReceiverImplementation2 = address(new 
            SimpleReceiver(
                address(core), 
                address(emissionsController)
            )
        );
        simpleReceiverFactory.setImplementation(simpleReceiverImplementation2);

        receiver2 = simpleReceiverFactory.deployNewReceiver("Test Receiver", new address[](0));
        vm.stopPrank();

        assertEq(receiver2, simpleReceiverFactory.getDeterministicAddress("Test Receiver"));
        assertEq(receiver2, simpleReceiverFactory.getReceiverByName("Test Receiver"));
    }

    function test_FactoryAccessControl() public {
        vm.expectRevert("!core");
        simpleReceiverFactory.setImplementation(address(0));

        vm.expectRevert("!core");
        simpleReceiverFactory.deployNewReceiver("Test Receiver", new address[](0));
    }

    function test_ReceiverAccessControl() public {
        address[] memory approvedClaimers = new address[](1);
        approvedClaimers[0] = user1;
        vm.prank(address(core));
        SimpleReceiver receiver = SimpleReceiver(simpleReceiverFactory.deployNewReceiver("Test Receiver", approvedClaimers));

        vm.prank(address(core));
        emissionsController.registerReceiver(address(receiver));

        skip(epochLength * (emissionsController.BOOTSTRAP_EPOCHS() + 1));

        vm.prank(address(user2));
        vm.expectRevert("Not approved claimer");
        receiver.claimEmissions(address(user2));

        vm.prank(address(user1));
        uint256 amount = receiver.claimEmissions(address(user1));
        assertGt(amount, 0);

        skip(epochLength);

        vm.prank(address(core));
        amount = receiver.claimEmissions(address(user1));
        assertGt(amount, 0);
    }
}
