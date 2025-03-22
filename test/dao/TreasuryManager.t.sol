// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Setup } from "../Setup.sol";
import { TreasuryManager } from "src/dao/operators/TreasuryManager.sol";
import { ICore } from "src/interfaces/ICore.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IAuthHook } from "src/interfaces/IAuthHook.sol";

contract TreasuryManagerTest is Setup {
    TreasuryManager public treasuryManager;
    address public constant TEST_TOKEN = address(0xBEEF);
    uint256 public constant TEST_AMOUNT = 1000e18;

    event TokenRetrieved(address indexed token, address indexed to, uint256 amount);
    event ETHRetrieved(address indexed to, uint256 amount);
    event TokenApprovalSet(address indexed token, address indexed spender, uint256 amount);
    event ExecutionPerformed(address indexed target, bytes data);

    function setUp() public override {
        super.setUp();
        
        // Deploy TreasuryManager
        treasuryManager = new TreasuryManager(address(core), address(registry));

        // Set up permissions in core for all treasury functions
        vm.startPrank(address(core));
        core.setOperatorPermissions(
            address(treasuryManager),
            address(treasury),
            IERC20.transfer.selector,
            true,
            IAuthHook(address(0))
        );
        
        // Add permissions for each treasury function
        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = bytes4(keccak256("retrieveToken(address,address)"));
        selectors[1] = bytes4(keccak256("retrieveTokenExact(address,address,uint256)"));
        selectors[2] = bytes4(keccak256("retrieveETH(address)"));
        selectors[3] = bytes4(keccak256("retrieveETHExact(address,uint256)"));
        selectors[4] = bytes4(keccak256("setTokenApproval(address,address,uint256)"));
        selectors[5] = bytes4(keccak256("execute(address,bytes)"));
        selectors[6] = bytes4(keccak256("safeExecute(address,bytes)"));

        for(uint i = 0; i < selectors.length; i++) {
            core.setOperatorPermissions(
                address(treasuryManager),
                address(treasury),
                selectors[i],
                true,
                IAuthHook(address(0))
            );
        }
        vm.stopPrank();

        // Setup test token
        deal(TEST_TOKEN, address(treasury), TEST_AMOUNT);
    }

    function test_RetrieveToken() public {
        address recipient = address(0xCAFE);
        
        vm.expectEmit(true, true, false, false);
        emit TokenRetrieved(TEST_TOKEN, recipient, 0);

        vm.prank(address(core));
        treasuryManager.retrieveToken(TEST_TOKEN, recipient);
        
        assertEq(IERC20(TEST_TOKEN).balanceOf(recipient), TEST_AMOUNT);
    }

    function test_RetrieveTokenExact() public {
        address recipient = address(0xCAFE);
        uint256 amount = TEST_AMOUNT / 2;

        vm.expectEmit(true, true, false, true);
        emit TokenRetrieved(TEST_TOKEN, recipient, amount);

        vm.prank(address(core));
        treasuryManager.retrieveTokenExact(TEST_TOKEN, recipient, amount);
        
        assertEq(IERC20(TEST_TOKEN).balanceOf(recipient), amount);
    }

    function test_RetrieveETH() public {
        address recipient = address(0xCAFE);
        deal(address(treasury), TEST_AMOUNT);
        
        vm.expectEmit(true, false, false, false);
        emit ETHRetrieved(recipient, 0);

        vm.prank(address(core));
        treasuryManager.retrieveETH(recipient);
        
        assertEq(recipient.balance, TEST_AMOUNT);
    }

    function test_RetrieveETHExact() public {
        address recipient = address(0xCAFE);
        deal(address(treasury), TEST_AMOUNT);
        uint256 amount = TEST_AMOUNT / 2;

        vm.expectEmit(true, false, false, true);
        emit ETHRetrieved(recipient, amount);

        vm.prank(address(core));
        treasuryManager.retrieveETHExact(recipient, amount);
        
        assertEq(recipient.balance, amount);
    }

    function test_SetTokenApproval() public {
        address spender = address(0xCAFE);
        
        vm.expectEmit(true, true, false, true);
        emit TokenApprovalSet(TEST_TOKEN, spender, TEST_AMOUNT);

        vm.prank(address(core));
        treasuryManager.setTokenApproval(TEST_TOKEN, spender, TEST_AMOUNT);
        
        assertEq(IERC20(TEST_TOKEN).allowance(address(treasury), spender), TEST_AMOUNT);
    }

    function test_Execute() public {
        address target = address(0xCAFE);
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, address(0xBEEF), 100);

        vm.expectEmit(true, false, false, true);
        emit ExecutionPerformed(target, data);

        vm.prank(address(core));
        (bool success,) = treasuryManager.execute(target, data);
        
        assertTrue(success);
    }

    function test_SafeExecute() public {
        address target = address(0xCAFE);
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, address(0xBEEF), 100);

        vm.expectEmit(true, false, false, true);
        emit ExecutionPerformed(target, data);

        vm.prank(address(core));
        bytes memory result = treasuryManager.safeExecute(target, data);
        
        assertTrue(result.length > 0);
    }

    function test_OnlyOwnerModifier() public {
        vm.prank(address(0xBABE));
        vm.expectRevert("!core");
        treasuryManager.retrieveToken(TEST_TOKEN, address(0xCAFE));
    }

    function test_FailedSafeExecute() public {
        address target = address(0);
        bytes memory data = "";

        vm.prank(address(core));
        vm.expectRevert("TreasuryManager: Safe execution failed");
        treasuryManager.safeExecute(target, data);
    }
}
