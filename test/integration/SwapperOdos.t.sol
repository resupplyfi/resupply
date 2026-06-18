// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { console } from "lib/forge-std/src/console.sol";
import { RouterSwapper } from "src/protocol/swappers/RouterSwapper.sol";
import { PairTestBase } from "test/integration/PairTestBase.t.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "src/interfaces/IERC4626.sol";
import { OdosApi } from "test/utils/OdosApi.sol";

contract SwapperOdosTest is PairTestBase {
    RouterSwapper public swapper;
    address public weth = OdosApi.WETH;
    address public usdc = OdosApi.USDC;
    bytes public odosPayload;
    
    function setUp() public override {
        super.setUp();
        swapper = new RouterSwapper(address(core), OdosApi.ODOS_ROUTER, "Resupply Swapper: ODOS");
    }

    function test_Name() public view {
        assertEq(swapper.name(), "Resupply Swapper: ODOS");
    }

    function test_Router() public view {
        assertEq(swapper.router(), OdosApi.ODOS_ROUTER);
    }

    function test_OdosApiV3RouterInfo() public {
        assertEq(OdosApi.getRouterV3(), OdosApi.ODOS_ROUTER);
    }

    function test_LiveOdosSwap() public {
        address collateral = address(pair.collateral());
        vm.startPrank(address(core));
        swapper.updateApprovals();
        pair.setSwapper(address(swapper), true);
        vm.stopPrank();
        
        uint256 borrowAmount = 50_000e18;
        odosPayload = OdosApi.getPayload(
            address(stablecoin),    // input token
            collateral,             // output token
            borrowAmount,           // input amount
            3,                      // slippage pct
            address(pair)           // recipient address
        );
        if (odosPayload.length == 0) vm.skip(true);
        address[] memory path = swapper.encode(odosPayload, address(stablecoin), collateral);
        console.log("Odos payload:", _bytesToFullHex(odosPayload));
        assertGt(odosPayload.length, 0, "API returned empty payload for leveragedPosition");

        uint256 initialUnderlyingAmount = 100_000e18;
        IERC20 underlying = IERC20(pair.underlying());
        deal(address(underlying), address(this), initialUnderlyingAmount);
        underlying.approve(address(pair), initialUnderlyingAmount);
        uint256 minCollateralOut = IERC4626(collateral).convertToShares(borrowAmount) * 9800 / 10000;
        console.log("-- Leveraging position --");
        console.log("Borrow Amt:", borrowAmount);
        console.log("Min collateral out:", minCollateralOut);
        uint256 collatBefore = pair.userCollateralBalance(address(this)) + IERC4626(collateral).convertToShares(initialUnderlyingAmount);
        pair.leveragedPosition(
            address(swapper), 
            borrowAmount,               // borrow amount
            initialUnderlyingAmount,    // initial collateral amount
            minCollateralOut,           // amount collateral out min
            path                        // encoded path
        );
        uint256 collatAfter = pair.userCollateralBalance(address(this));
        console.log("Collateral delta:", collatAfter - collatBefore);

        uint256 amount = borrowAmount / 2;
        odosPayload = OdosApi.getPayload(
            collateral,             // input token
            address(stablecoin),    // output token
            amount,                 // input amount
            3,                      // slippage pct
            address(pair)           // recipient address
        );
        if (odosPayload.length == 0) vm.skip(true);
        path = swapper.encode(odosPayload, collateral, address(stablecoin));
        bytes memory decodedPayload = swapper.decode(path);
        assertGt(decodedPayload.length, 0, "API returned empty payload for repayWithCollateral");
        
        assertEq(keccak256(decodedPayload), keccak256(odosPayload), "Decoded payload does not match original payload");
        uint256 minAmountOut = IERC4626(collateral).convertToAssets(amount);
        console.log("-- Repaying with collateral --");
        console.log("Collateral Amt:", amount);
        console.log("Min amount reUSD out:", minAmountOut);
        uint256 borrowBefore = pair.userBorrowShares(address(this));
        borrowBefore = toAmount(pair, borrowBefore);
        pair.repayWithCollateral(
            address(swapper),   // swapper address
            amount,             // collateral amount to swap
            minAmountOut,       // amount out min
            path                // path
        );
        uint256 borrowAfter = pair.userBorrowShares(address(this));
        borrowAfter = toAmount(pair, borrowAfter);
        console.log("Borrow delta:", borrowBefore - borrowAfter);
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
        console.log("Can update approvals:", canUpdateApprovals);
        swapper.updateApprovals();
        address[] memory pairs = registry.getAllPairAddresses();
        assertGt(pairs.length, 0);
        for (uint i = 0; i < pairs.length; i++) {
            address _pair = pairs[i];
            address collateral = address(IResupplyPair(_pair).collateral());
            address odosRouter = swapper.router();
            assertGt(IERC20(collateral).allowance(address(swapper), odosRouter), 1e40);
        }
        assertEq(swapper.canUpdateApprovals(), false);
    }

    function test_RevokeApprovals() public {
        vm.prank(swapper.owner());
        swapper.revokeApprovals();
        address[] memory pairs = registry.getAllPairAddresses();
        assertGt(pairs.length, 0);
        for (uint i = 0; i < pairs.length; i++) {
            address _pair = pairs[i];
            address collateral = address(IResupplyPair(_pair).collateral());
            address odosRouter = swapper.router();
            assertEq(IERC20(collateral).allowance(address(swapper), odosRouter), 0);
        }
        assertEq(IERC20(swapper.reusd()).allowance(address(swapper), swapper.router()), 0);
        vm.expectRevert("approvals revoked");
        swapper.swap(address(this), 0, new address[](0), address(this));
    }

    function test_EncodeDecodePayload() public {
        // At time of writing tests, our collateral tokens are not yet supported by Odos, so we use WETH/USDC for testing
        deal(weth, address(swapper), 100e18);
        vm.prank(address(swapper));
        IERC20(weth).approve(swapper.router(), type(uint256).max);
        odosPayload = OdosApi.getPayloadForWethToUsdc(1e18, 3, address(this));
        if (odosPayload.length == 0) vm.skip(true);
        odosPayload = abi.encodePacked(
            odosPayload,
            "111" // add some extra data to the payload to help test that we are trimming properly
        );
        bytes memory decodedPayload = swapper.decode(swapper.encode(odosPayload, weth, usdc));
        // Verify the payload was correctly encoded and decoded
        assertEq(keccak256(odosPayload), keccak256(decodedPayload), "Original and decoded payloads don't match");
    }
    
    // Helper to convert full bytes array to hex string for visual comparison
    function _bytesToFullHex(bytes memory data) internal pure returns (string memory) {
        bytes memory hexBytes = new bytes(2 * data.length + 2);
        hexBytes[0] = "0";
        hexBytes[1] = "x";
        
        for (uint i = 0; i < data.length; i++) {
            uint8 b = uint8(data[i]);
            hexBytes[2 + i*2] = _hexChar(b / 16);
            hexBytes[3 + i*2] = _hexChar(b % 16);
        }
        
        return string(hexBytes);
    }
    
    // Helper to convert a byte to hex character
    function _hexChar(uint8 value) internal pure returns (bytes1) {
        if (value < 10) {
            return bytes1(uint8(bytes1("0")) + value);
        } else {
            return bytes1(uint8(bytes1("a")) + value - 10);
        }
    }

    function toAmount(IResupplyPair _pair, uint256 shares) internal view returns (uint256 amount) {
        (uint256 totalBorrow, uint256 totalBorrowShares) = _pair.totalBorrow();
        if (totalBorrowShares == 0) {
            amount = shares;
        } else {
            amount = (shares * totalBorrow) / totalBorrowShares;
            if (true && totalBorrow > 0 && (amount * totalBorrowShares) / totalBorrow < shares) {
                amount = amount + 1;
            }
        }
    }
}
