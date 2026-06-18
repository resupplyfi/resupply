// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { RouterSwapper } from "src/protocol/swappers/RouterSwapper.sol";
import { PairTestBase } from "test/integration/PairTestBase.t.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { EnsoApi } from "test/utils/EnsoApi.sol";

contract SwapperEnsoTest is PairTestBase {
    RouterSwapper public swapper;
    bytes public ensoPayload;

    function setUp() public override {
        super.setUp();
        swapper = new RouterSwapper(address(core), EnsoApi.ENSO_ROUTER, "Resupply Swapper: ENSO");
    }

    function test_Name() public view {
        assertEq(swapper.name(), "Resupply Swapper: ENSO");
    }

    function test_Router() public view {
        assertEq(swapper.router(), EnsoApi.ENSO_ROUTER);
    }

    function test_RecoverERC20() public {
        deal(address(stablecoin), address(swapper), 1e18);
        address recipient = address(core);
        uint256 balanceBefore = stablecoin.balanceOf(recipient);
        uint256 amount = stablecoin.balanceOf(address(swapper));
        vm.prank(address(core));
        swapper.recoverERC20(address(stablecoin), amount);
        assertEq(stablecoin.balanceOf(address(swapper)), 0);
        assertEq(stablecoin.balanceOf(recipient) - balanceBefore, 1e18);
    }

    function test_UpdateApprovals() public {
        bool canUpdateApprovals = swapper.canUpdateApprovals();
        swapper.updateApprovals();
        address[] memory pairs = registry.getAllPairAddresses();
        assertGt(pairs.length, 0);
        for (uint256 i = 0; i < pairs.length; i++) {
            address collateral = address(IResupplyPair(pairs[i]).collateral());
            assertGt(IERC20(collateral).allowance(address(swapper), swapper.router()), 1e40);
        }
        assertTrue(canUpdateApprovals);
        assertEq(swapper.canUpdateApprovals(), false);
    }

    function test_RevokeApprovals() public {
        swapper.updateApprovals();
        vm.prank(swapper.owner());
        swapper.revokeApprovals();
        address[] memory pairs = registry.getAllPairAddresses();
        assertGt(pairs.length, 0);
        for (uint256 i = 0; i < pairs.length; i++) {
            address collateral = address(IResupplyPair(pairs[i]).collateral());
            assertEq(IERC20(collateral).allowance(address(swapper), swapper.router()), 0);
        }
        assertEq(IERC20(swapper.reusd()).allowance(address(swapper), swapper.router()), 0);
        assertTrue(swapper.approvalsRevoked());
        assertFalse(swapper.canUpdateApprovals());
        vm.expectRevert("approvals revoked");
        swapper.swap(address(this), 0, new address[](0), address(this));
    }

    function test_EncodeDecodePayloadFromProviderApi() public {
        ensoPayload = EnsoApi.getPayload(EnsoApi.WETH, EnsoApi.USDC, 1e18, 300, address(swapper), address(this));
        ensoPayload = abi.encodePacked(ensoPayload, "111");
        bytes memory decodedPayload = swapper.decode(swapper.encode(ensoPayload, EnsoApi.WETH, EnsoApi.USDC));
        assertEq(keccak256(ensoPayload), keccak256(decodedPayload), "Original and decoded payloads don't match");
    }
}
