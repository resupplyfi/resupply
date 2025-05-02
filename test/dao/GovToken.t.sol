pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "src/Constants.sol" as Constants;
import { Setup } from "../Setup.sol";
import { GovTokenHarness } from "../mocks/GovTokenHarness.sol";

contract TreasuryTest is Setup {

    function setUp() public override {
        super.setUp();
        
        // clear balance of user 1
        uint256 balance = govToken.balanceOf(user1);
        vm.prank(user1);
        govToken.transfer(address(treasury), balance);
    }

    function test_SetMinter() public {
        vm.prank(address(core));
        govToken.setMinter(address(user1));

        vm.prank(address(user1));
        govToken.mint(address(user1), 1000);
        assertEq(govToken.balanceOf(address(user1)), 1000);

        vm.prank(address(core));
        vm.expectRevert("!minter");
        govToken.mint(address(user1), 1000);

        vm.prank(address(core));
        govToken.setMinter(address(user2));

        vm.prank(address(core));
        govToken.finalizeMinter();

        vm.prank(address(core));
        vm.expectRevert("minter finalized");
        govToken.setMinter(address(user1));

        vm.prank(address(core));
        vm.expectRevert("minter finalized");
        govToken.finalizeMinter();
    }

    function test_GlobalSupplyNotReducedByBurns() public {
        // this harness implements a public `burn` function, to mimic the OFT
        // we want to ensure that, unlike `totalSupply`, the `globalSupply` is not reduced by burns
        GovTokenHarness token = new GovTokenHarness(address(core), address(user1), 1_000_000e18, Constants.Mainnet.LAYERZERO_ENDPOINTV2, "Test", "TEST");
        uint256 amount = 1_000_000e18;
        deal(address(token), address(this), amount);
        uint256 startSupply = token.totalSupply();
        token.burn(amount);
        uint256 endSupply = token.totalSupply();
        assertEq(startSupply, endSupply + amount);
        assertEq(token.globalSupply(), startSupply);
        assertGt(token.globalSupply(), token.totalSupply());
    }

    function test_GlobalSupplyIncreasesByMints() public {
        // this harness implements a public `burn` function, to mimic the OFT
        // we want to ensure that, unlike `totalSupply`, the `globalSupply` is not reduced by burns
        uint256 amount = 1_000_000e18;
        
        vm.prank(address(core));
        govToken.setMinter(address(this));
        
        uint256 startGlobalSupply = govToken.globalSupply();
        govToken.mint(address(this), amount);
        
        assertEq(govToken.globalSupply(), startGlobalSupply + amount);
        assertEq(govToken.globalSupply(), govToken.totalSupply());
        assertGt(govToken.globalSupply(), startGlobalSupply);
    }
}
