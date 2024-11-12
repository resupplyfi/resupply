pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Setup } from "../utils/Setup.sol";
import { SimpleReceiverFactory } from "../../../src/dao/emissions/receivers/SimpleReceiverFactory.sol";
import { SimpleReceiver } from "../../../src/dao/emissions/receivers/SimpleReceiver.sol";
import { GovToken } from "../../../src/dao/GovToken.sol";

contract SimpleReceiverFactoryTest is Setup {

    address public simpleReceiverImplementation;
    SimpleReceiverFactory public simpleReceiverFactory;
    uint256 public epochLength;

    function setUp() public override {
        super.setUp();
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
        epochLength = emissionsController.epochLength();
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
