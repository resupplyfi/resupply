pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Setup } from "../utils/Setup.sol";
import { EmissionsController } from "../../../src/dao/emissions/EmissionsController.sol";
import { GovToken } from "../../../src/dao/GovToken.sol";

contract EmissionsControllerTest is Setup {
    uint256 public epochLength;

    function setUp() public override {
        super.setUp();
        vm.startPrank(address(core));
        govToken.setEmissionsController(address(emissionsController));
        epochLength = emissionsController.epochLength();
        // Do this to get some totalSupply
        govToken.initialize(address(0x99999), 1000000 * 10 ** 18);
        vm.stopPrank();
    }

    function test_EmissionsSchedule() public {
        uint256 epoch;
        for (uint256 i = 0; i < 10; i++) {
            emissionsController.fetchEmissions();
            skip(epochLength);
            vm.roll(block.number + 1);
            epoch = emissionsController.getEpoch();
            console2.log('Epoch', i, epoch, emissionsController.emissionsPerEpoch(i));
        }
    }
}
