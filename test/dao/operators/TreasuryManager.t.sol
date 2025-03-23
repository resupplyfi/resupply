// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Setup } from "test/Setup.sol";
import { TreasuryManager } from "src/dao/operators/TreasuryManager.sol";
import { ICore } from "src/interfaces/ICore.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IAuthHook } from "src/interfaces/IAuthHook.sol";
import { ITreasury } from "src/interfaces/ITreasury.sol";

contract TreasuryManagerTest is Setup {
    address public token;
    TreasuryManager public treasuryManager;
    uint256 public constant TEST_AMOUNT = 1000e18;

    event TokenRetrieved(address indexed token, address indexed to, uint256 amount);
    event ETHRetrieved(address indexed to, uint256 amount);
    event TokenApprovalSet(address indexed token, address indexed spender, uint256 amount);
    event ExecutionPerformed(address indexed target, bytes data);

    function setUp() public override {
        super.setUp();
        token = address(stablecoin);
        treasuryManager = new TreasuryManager(address(core), address(treasury));
        
        // Add permissions for each treasury function
        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = ITreasury.retrieveToken.selector;
        selectors[1] = ITreasury.retrieveTokenExact.selector;
        selectors[2] = ITreasury.retrieveETH.selector;
        selectors[3] = ITreasury.retrieveETHExact.selector;
        selectors[4] = ITreasury.setTokenApproval.selector;
        selectors[5] = ITreasury.execute.selector;
        selectors[6] = ITreasury.safeExecute.selector;
        vm.startPrank(address(core));
        for(uint i = 0; i < selectors.length; i++) {
            core.setOperatorPermissions(
                address(treasuryManager),
                address(treasury),
                selectors[i],
                true,
                IAuthHook(address(0))
            );
        }
        treasuryManager.setManager(dev);
        vm.stopPrank();
        // Setup test token
        deal(token, address(treasury), TEST_AMOUNT);
    }

    function test_RetrieveToken() public {
        address recipient = address(123);
        vm.prank(dev);
        treasuryManager.retrieveToken(token, recipient);
        assertEq(IERC20(token).balanceOf(recipient), TEST_AMOUNT);
    }

    function test_RetrieveTokenExact() public {
        address recipient = address(123);
        uint256 amount = TEST_AMOUNT / 2;
        vm.prank(dev);
        treasuryManager.retrieveTokenExact(token, recipient, amount);
        assertEq(IERC20(token).balanceOf(recipient), amount);
    }

    function test_RetrieveETH() public {
        address recipient = address(123);
        deal(address(treasury), TEST_AMOUNT);
        vm.prank(dev);
        treasuryManager.retrieveETH(recipient);
        assertEq(recipient.balance, TEST_AMOUNT);
    }

    function test_RetrieveETHExact() public {
        address recipient = address(123);
        deal(address(treasury), TEST_AMOUNT);
        uint256 amount = TEST_AMOUNT / 2;
        vm.prank(dev);
        treasuryManager.retrieveETHExact(recipient, amount);
        assertEq(recipient.balance, amount);
    }

    function test_SetTokenApproval() public {
        address spender = address(123);
        vm.prank(dev);
        treasuryManager.setTokenApproval(token, spender, TEST_AMOUNT);
        assertEq(IERC20(token).allowance(address(treasury), spender), TEST_AMOUNT);
    }

    function test_Execute() public {
        address target = address(stablecoin);
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, address(0xBEEF), 100);
        vm.prank(dev);
        (bool success,) = treasuryManager.execute(target, data);
        assertTrue(success);
    }

    function test_SafeExecute() public {
        deal(token, address(treasury), TEST_AMOUNT);
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, address(0xBEEF), 100);
        vm.prank(dev);
        bytes memory result = treasuryManager.safeExecute(token, data);
        bool success = abi.decode(result, (bool));
        assertTrue(success);
    }

    function test_OnlyManagerModifier() public {
        vm.prank(address(core));
        vm.expectRevert("!manager");
        treasuryManager.retrieveToken(token, address(0xCAFE));
    }

    function test_FailedExecute() public {
        address target = address(core);
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, address(0xBEEF), 100);
        vm.prank(dev);
        (bool success,) = treasuryManager.execute(target, data);
        assertFalse(success);
    }
}
