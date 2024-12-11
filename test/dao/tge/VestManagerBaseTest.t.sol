
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import { Setup } from "../../Setup.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract VestManagerBaseTest is Setup {

    function setUp() public override {
        super.setUp();
        vm.prank(address(core));
        govToken.approve(address(vestManager), type(uint256).max);
    }
}
