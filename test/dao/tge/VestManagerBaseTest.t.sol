
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

    function printAggregatedData(address _account) public {
        (uint256 claimable, uint256 locked, uint256 claimed, uint256 vested) = vestManager.getAggregatedAccountData(_account);
        console.log("----- Aggregated data -----");
        console.log("claimable", claimable);
        console.log("locked", locked);
        console.log("claimed", claimed);
        console.log("vested", vested);
    }
}
