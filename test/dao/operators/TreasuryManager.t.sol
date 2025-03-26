// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Setup } from "test/Setup.sol";
import { TreasuryManager } from "src/dao/operators/TreasuryManager.sol";
import { ICore } from "src/interfaces/ICore.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IAuthHook } from "src/interfaces/IAuthHook.sol";
import { ITreasury } from "src/interfaces/ITreasury.sol";
import { IPrismaCore } from "src/interfaces/IPrismaCore.sol";
import { ISimpleReceiver } from "src/interfaces/ISimpleReceiver.sol";
import { SimpleReceiver } from "src/dao/emissions/receivers/SimpleReceiver.sol";
import { EmissionsController } from "src/dao/emissions/EmissionsController.sol";

contract TreasuryManagerTest is Setup {
    address public token;
    TreasuryManager public treasuryManager;
    uint256 public constant TEST_AMOUNT = 1000e18;
    address public prismaFeeReceiver = 0xfdCE0267803C6a0D209D3721d2f01Fd618e9CBF8;
    IPrismaCore public prismaCore = IPrismaCore(0x5d17eA085F2FF5da3e6979D5d26F1dBaB664ccf8);
    ISimpleReceiver public receiver;

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
        core.setOperatorPermissions(
            address(treasuryManager), 
            address(prismaFeeReceiver), // can call on any target
            bytes4(keccak256("transferToken(address,address,uint256)")),
            true,
            IAuthHook(address(0)) // auth hook
        );
        core.setOperatorPermissions(
            address(treasuryManager), 
            address(prismaFeeReceiver), // can call on any target
            bytes4(keccak256("setTokenApproval(address,address,uint256)")),
            true,
            IAuthHook(address(0)) // auth hook
        );
        treasuryManager.setManager(dev);
        vm.stopPrank();
        // Setup test token
        deal(token, address(treasury), TEST_AMOUNT);
        vm.prank(prismaCore.owner());
        prismaCore.commitTransferOwnership(address(core));
        skip(3 days);
        vm.prank(address(core));
        prismaCore.acceptTransferOwnership();
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

    function test_TransferTokenFromPrismaFeeReceiver() public {
        deal(address(stablecoin), prismaFeeReceiver, 100e18);
        vm.prank(dev);
        treasuryManager.transferTokenFromPrismaFeeReceiver(address(stablecoin), address(user1), 100e18);
        assertEq(stablecoin.balanceOf(address(user1)), 100e18);
    }

    function test_ApproveTokenFromPrismaFeeReceiver() public {
        vm.prank(dev);
        treasuryManager.approveTokenFromPrismaFeeReceiver(address(stablecoin), address(user1), 100e18);
        assertEq(stablecoin.allowance(address(prismaFeeReceiver), address(user1)), 100e18);
    }

    function test_Execute() public {
        address target = address(stablecoin);
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, address(0x123), 100);
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

    function test_ClaimLpIncentives() public {
        setUpEmissions();
        address manager = treasuryManager.manager();
        uint256 balance = govToken.balanceOf(address(treasuryManager));
        skip(epochLength);
        vm.prank(dev);
        treasuryManager.claimLpIncentives();
        assertGt(govToken.balanceOf(manager),balance);
    }

    function test_RecoverERC20() public {
        address manager = treasuryManager.manager();
        uint256 startBalance = IERC20(token).balanceOf(manager);
        deal(token, address(treasuryManager), TEST_AMOUNT);
        vm.prank(dev);
        treasuryManager.recoverERC20(IERC20(token));
        assertGt(IERC20(token).balanceOf(manager), startBalance);
    }

    function test_ViewPermissions() public {
        (
            bool retrieveToken, 
            bool retrieveTokenExact, 
            bool retrieveETH, 
            bool retrieveETHExact, 
            bool setTokenApproval, 
            bool execute, 
            bool safeExecute,
            bool transferTokenFromPrismaFeeReceiver,
            bool approveTokenFromPrismaFeeReceiver
        ) = treasuryManager.viewPermissions();
        assertEq(retrieveToken, true, "retrieveToken permission not set");
        assertEq(retrieveTokenExact, true, "retrieveTokenExact permission not set");
        assertEq(retrieveETH, true, "retrieveETH permission not set");
        assertEq(retrieveETHExact, true, "retrieveETHExact permission not set");
        assertEq(setTokenApproval, true, "setTokenApproval permission not set");
        assertEq(execute, true, "execute permission not set");
        assertEq(safeExecute, true, "safeExecute permission not set");
        assertEq(transferTokenFromPrismaFeeReceiver, true, "transferTokenFromPrismaFeeReceiver permission not set");
        assertEq(approveTokenFromPrismaFeeReceiver, true, "approveTokenFromPrismaFeeReceiver permission not set");

        setPermission(address(treasury), ITreasury.retrieveToken.selector, false);
        setPermission(address(treasury), ITreasury.retrieveTokenExact.selector, false);
        setPermission(address(treasury), ITreasury.retrieveETH.selector, false);
        setPermission(address(treasury), ITreasury.retrieveETHExact.selector, false);
        setPermission(address(treasury), ITreasury.setTokenApproval.selector, false);
        setPermission(address(treasury), ITreasury.execute.selector, false);
        setPermission(address(treasury), ITreasury.safeExecute.selector, false);
        setPermission(address(prismaFeeReceiver), bytes4(keccak256("transferToken(address,address,uint256)")), false);
        setPermission(address(prismaFeeReceiver), bytes4(keccak256("setTokenApproval(address,address,uint256)")), false);

        (
            retrieveToken, 
            retrieveTokenExact, 
            retrieveETH, 
            retrieveETHExact, 
            setTokenApproval, 
            execute, 
            safeExecute, 
            transferTokenFromPrismaFeeReceiver, 
            approveTokenFromPrismaFeeReceiver
        ) = treasuryManager.viewPermissions();
        assertEq(retrieveToken, false, "retrieveToken still set");
        assertEq(retrieveTokenExact, false, "retrieveTokenExact still set");
        assertEq(retrieveETH, false, "retrieveETH still set");
        assertEq(retrieveETHExact, false, "retrieveETHExact still set");
        assertEq(setTokenApproval, false, "setTokenApproval still set");
        assertEq(execute, false, "execute still set");
        assertEq(safeExecute, false, "safeExecute still set");
        assertEq(transferTokenFromPrismaFeeReceiver, false, "transferTokenFromPrismaFeeReceiver still set");
        assertEq(approveTokenFromPrismaFeeReceiver, false, "approveTokenFromPrismaFeeReceiver still set");
    }

    function setPermission(address target, bytes4 selector, bool authorized) public {
        vm.prank(address(core));
        core.setOperatorPermissions(
            address(treasuryManager),
            target,
            selector,
            authorized,
            IAuthHook(address(0))
        );
    }

    function setUpEmissions() public {
        emissionsController = new EmissionsController(
            address(core), // core
            address(govToken), // govtoken
            getEmissionsSchedule(), // emissions
            1, // epochs per
            0, // tail rate
            0 // bootstrap epochs
        );
        vm.prank(address(core));
        govToken.setMinter(address(emissionsController));
        receiver = ISimpleReceiver(address(new 
            SimpleReceiver(
                address(core), 
                address(emissionsController)
            )
        ));
        vm.prank(address(core));
        emissionsController.registerReceiver(address(receiver));
        skip(epochLength);
        vm.prank(address(core));
        receiver.setApprovedClaimer(address(treasuryManager), true);
        vm.prank(dev);
        treasuryManager.setLpIncentivesReceiver(address(receiver));
    }
}
