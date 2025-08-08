// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { console } from "forge-std/console.sol";
import { Protocol, DeploymentConfig } from "src/Constants.sol";
import { TreasuryManagerUpgradeable } from "src/dao/operators/TreasuryManagerUpgradeable.sol";
import { Upgrades, UnsafeUpgrades } from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import { Options } from "@openzeppelin/foundry-upgrades/Options.sol";
import { BaseUpgradeableOperatorTest } from "test/utils/BaseUpgradeableOperator.sol";
import { IPrismaCore } from "src/interfaces/prisma/IPrismaCore.sol";
import { ISimpleReceiver } from "src/interfaces/ISimpleReceiver.sol";
import { SimpleReceiver } from "src/dao/emissions/receivers/SimpleReceiver.sol";
import { EmissionsController } from "src/dao/emissions/EmissionsController.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IAuthHook } from "src/interfaces/IAuthHook.sol";
import { ITreasury } from "src/interfaces/ITreasury.sol";
import { ICore } from "src/interfaces/ICore.sol";
import { Setup } from "test/e2e/Setup.sol";

contract TreasuryManagerUpgradeableTest is Setup, BaseUpgradeableOperatorTest {
    address public token;
    TreasuryManagerUpgradeable public treasuryManager;
    ISimpleReceiver public receiver;
    uint256 public constant TEST_AMOUNT = 1000e18;
    address public prismaFeeReceiver = 0xfdCE0267803C6a0D209D3721d2f01Fd618e9CBF8;
    IPrismaCore public prismaCore = IPrismaCore(0x5d17eA085F2FF5da3e6979D5d26F1dBaB664ccf8);

    event TokenRetrieved(address indexed token, address indexed to, uint256 amount);
    event ETHRetrieved(address indexed to, uint256 amount);
    event TokenApprovalSet(address indexed token, address indexed spender, uint256 amount);
    event ExecutionPerformed(address indexed target, bytes data);

    function setUp() public override {
        super.setUp();
        deployProxyAndImplementation();
        treasuryManager = TreasuryManagerUpgradeable(proxy);
        token = address(stablecoin);
        setCorePermissions();
        transferPrismaOwnership();
        deal(token, address(treasury), TEST_AMOUNT);
    }

    // Implement abstract functions from BaseUpgradeableOperatorTest
    function initialize() internal override {TreasuryManagerUpgradeable(proxy).initialize(address(this));}
    function getContractNameV1() internal view override returns (string memory) {return "TreasuryManagerUpgradeable.sol:TreasuryManagerUpgradeable";}
    function getContractNameV2() internal view override returns (string memory) {return "TreasuryManagerUpgradeable.sol:TreasuryManagerUpgradeable";}
    function getInitializerData() internal view override returns (bytes memory) {return abi.encodeCall(TreasuryManagerUpgradeable.initialize, address(this));}

    function test_TreasuryManagerSet() public {
        assertEq(treasuryManager.manager(), address(this));
        assertEq(TreasuryManagerUpgradeable(proxy).manager(), address(this));
    }

    function test_TreasuryManagerSet_NotOwner() public {
        vm.prank(address(1));
        vm.expectRevert("!owner");
        TreasuryManagerUpgradeable(proxy).setManager(address(1));
    }

    function test_RetrieveToken() public {
        address recipient = address(123);
        treasuryManager.retrieveToken(token, recipient);
        assertEq(IERC20(token).balanceOf(recipient), TEST_AMOUNT);
    }

    function test_RetrieveTokenExact() public {
        address recipient = address(123);
        uint256 amount = TEST_AMOUNT / 2;
        treasuryManager.retrieveTokenExact(token, recipient, amount);
        assertEq(IERC20(token).balanceOf(recipient), amount);
    }

    function test_RetrieveETH() public {
        address recipient = address(123);
        deal(address(treasury), TEST_AMOUNT);
        treasuryManager.retrieveETH(recipient);
        assertEq(recipient.balance, TEST_AMOUNT);
    }

    function test_RetrieveETHExact() public {
        address recipient = address(123);
        deal(address(treasury), TEST_AMOUNT);
        uint256 amount = TEST_AMOUNT / 2;
        treasuryManager.retrieveETHExact(recipient, amount);
        assertEq(recipient.balance, amount);
    }

    function test_SetTokenApproval() public {
        console.log("manager", treasuryManager.manager());
        console.log("core", address(core));
        console.log("core", address(treasuryManager.core()));
        address spender = address(123);
        treasuryManager.setTokenApproval(token, spender, TEST_AMOUNT);
        assertEq(IERC20(token).allowance(address(treasury), spender), TEST_AMOUNT);
    }

    function test_TransferTokenFromPrismaFeeReceiver() public {
        deal(address(stablecoin), prismaFeeReceiver, 100e18);
        treasuryManager.transferTokenFromPrismaFeeReceiver(address(stablecoin), address(user1), 100e18);
        assertEq(stablecoin.balanceOf(address(user1)), 100e18);
    }

    function test_ApproveTokenFromPrismaFeeReceiver() public {
        console.log("manager", treasuryManager.manager());
        treasuryManager.approveTokenFromPrismaFeeReceiver(address(stablecoin), address(user1), 100e18);
        assertEq(stablecoin.allowance(address(prismaFeeReceiver), address(user1)), 100e18);
    }

    function test_Execute() public {
        address target = address(stablecoin);
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, address(0x123), 100);
        (bool success,) = treasuryManager.execute(target, data);
        assertTrue(success);
    }

    function test_SafeExecute() public {
        deal(token, address(treasury), TEST_AMOUNT);
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, address(0xBEEF), 100);
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
        (bool success,) = treasuryManager.execute(target, data);
        assertFalse(success);
    }

    function test_ClaimLpIncentives() public {
        setUpEmissions();
        address manager = treasuryManager.manager();
        uint256 balance = govToken.balanceOf(address(treasuryManager));
        skip(epochLength);
        treasuryManager.claimLpIncentives();
        assertGt(govToken.balanceOf(manager),balance);
    }

    function test_RecoverERC20() public {
        address manager = treasuryManager.manager();
        uint256 startBalance = IERC20(token).balanceOf(manager);
        deal(token, address(treasuryManager), TEST_AMOUNT);
        treasuryManager.recoverERC20(IERC20(token));
        assertGt(IERC20(token).balanceOf(manager), startBalance);
    }

    function test_ViewPermissions() public {
        TreasuryManagerUpgradeable.Permissions memory p = treasuryManager.viewPermissions();
        assertEq(p.retrieveToken, true, "retrieveToken permission not set");
        assertEq(p.retrieveTokenExact, true, "retrieveTokenExact permission not set");
        assertEq(p.retrieveETH, true, "retrieveETH permission not set");
        assertEq(p.retrieveETHExact, true, "retrieveETHExact permission not set");
        assertEq(p.setTokenApproval, true, "setTokenApproval permission not set");
        assertEq(p.execute, true, "execute permission not set");
        assertEq(p.safeExecute, true, "safeExecute permission not set");
        assertEq(p.transferTokenFromPrismaFeeReceiver, true, "transferTokenFromPrismaFeeReceiver permission not set");
        assertEq(p.approveTokenFromPrismaFeeReceiver, true, "approveTokenFromPrismaFeeReceiver permission not set");

        setPermission(address(treasury), ITreasury.retrieveToken.selector, false);
        setPermission(address(treasury), ITreasury.retrieveTokenExact.selector, false);
        setPermission(address(treasury), ITreasury.retrieveETH.selector, false);
        setPermission(address(treasury), ITreasury.retrieveETHExact.selector, false);
        setPermission(address(treasury), ITreasury.setTokenApproval.selector, false);
        setPermission(address(treasury), ITreasury.execute.selector, false);
        setPermission(address(treasury), ITreasury.safeExecute.selector, false);
        setPermission(address(prismaFeeReceiver), bytes4(keccak256("transferToken(address,address,uint256)")), false);
        setPermission(address(prismaFeeReceiver), bytes4(keccak256("setTokenApproval(address,address,uint256)")), false);

        p = treasuryManager.viewPermissions();
        assertEq(p.retrieveToken, false, "retrieveToken still set");
        assertEq(p.retrieveTokenExact, false, "retrieveTokenExact still set");
        assertEq(p.retrieveETH, false, "retrieveETH still set");
        assertEq(p.retrieveETHExact, false, "retrieveETHExact still set");
        assertEq(p.setTokenApproval, false, "setTokenApproval still set");
        assertEq(p.execute, false, "execute still set");
        assertEq(p.safeExecute, false, "safeExecute still set");
        assertEq(p.transferTokenFromPrismaFeeReceiver, false, "transferTokenFromPrismaFeeReceiver still set");
        assertEq(p.approveTokenFromPrismaFeeReceiver, false, "approveTokenFromPrismaFeeReceiver still set");
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
        treasuryManager.setLpIncentivesReceiver(address(receiver));
    }

    function setCorePermissions() public {
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
        vm.stopPrank();
        vm.prank(treasuryManager.owner());
        treasuryManager.setManager(address(this));
    }

    function transferPrismaOwnership() public {
        vm.prank(prismaCore.owner());
        prismaCore.commitTransferOwnership(address(core));
        skip(3 days);
        vm.prank(address(core));
        prismaCore.acceptTransferOwnership();
    }
}