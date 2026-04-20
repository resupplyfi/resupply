// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { console } from "lib/forge-std/src/console.sol";
import { SwapperLifi } from "src/protocol/SwapperLifi.sol";
import { PairTestBase } from "test/integration/PairTestBase.t.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "src/interfaces/IERC4626.sol";
import { LifiApi } from "test/utils/LifiApi.sol";

contract SwapperLifiTest is PairTestBase {
    SwapperLifi public swapper;
    bytes public lifiPayload;

    function setUp() public override {
        super.setUp();
        swapper = new SwapperLifi(address(core));
    }

    function test_Name() public view {
        assertEq(swapper.name(), "Resupply Swapper: LI.FI");
    }

    function test_LiveLifiSwap() public {
        address collateral = address(pair.collateral());
        vm.startPrank(address(core));
        swapper.updateApprovals();
        pair.setSwapper(address(swapper), true);
        vm.stopPrank();

        uint256 borrowAmount = 5000e18;
        LifiApi.Quote memory lifiQuote = LifiApi.getQuote(
            address(stablecoin), // input token
            collateral, // output token
            borrowAmount, // input amount
            20, // slippage pct
            address(swapper), // address that calls LI.FI
            address(pair) // recipient address
        );
        assertGt(lifiQuote.payload.length, 0, "API returned empty payload for leveragedPosition");
        assertGt(lifiQuote.amountOutMin, 0, "API returned zero minimum output");
        address[] memory path = swapper.encode(lifiQuote.payload, address(stablecoin), collateral);
        console.log("LI.FI payload:", _bytesToFullHex(lifiQuote.payload));

        uint256 initialUnderlyingAmount = 20_000e18;
        IERC20 underlying = IERC20(pair.underlying());
        deal(address(underlying), address(this), initialUnderlyingAmount);
        underlying.approve(address(pair), initialUnderlyingAmount);
        console.log("-- Leveraging position --");
        console.log("Borrow Amt:", borrowAmount);
        console.log("Min collateral out:", lifiQuote.amountOutMin);
        uint256 collatBefore = pair.userCollateralBalance(address(this)) + IERC4626(collateral).convertToShares(initialUnderlyingAmount);
        pair.leveragedPosition(
            address(swapper),
            borrowAmount, // borrow amount
            initialUnderlyingAmount, // initial collateral amount
            lifiQuote.amountOutMin, // amount collateral out min
            path // encoded path
        );
        uint256 collatAfter = pair.userCollateralBalance(address(this));
        console.log("Collateral delta:", collatAfter - collatBefore);

        uint256 amount = 500e18;
        assertGe(collatAfter - collatBefore, amount, "Not enough LI.FI collateral out");
        lifiQuote = LifiApi.getQuote(
            collateral, // input token
            address(stablecoin), // output token
            amount, // input amount
            20, // slippage pct
            address(swapper), // address that calls LI.FI
            address(pair) // recipient address
        );
        assertGt(lifiQuote.payload.length, 0, "API returned empty payload for repayWithCollateral");
        assertGt(lifiQuote.amountOutMin, 0, "API returned zero minimum output");
        path = swapper.encode(lifiQuote.payload, collateral, address(stablecoin));
        bytes memory decodedPayload = swapper.decode(path);
        assertEq(keccak256(decodedPayload), keccak256(lifiQuote.payload), "Decoded payload does not match original payload");
        console.log("-- Repaying with collateral --");
        console.log("Collateral Amt:", amount);
        console.log("Min reUSD out:", lifiQuote.amountOutMin);
        uint256 borrowBefore = pair.userBorrowShares(address(this));
        borrowBefore = toAmount(pair, borrowBefore);
        pair.repayWithCollateral(
            address(swapper), // swapper address
            amount, // collateral amount to swap
            lifiQuote.amountOutMin, // amount out min
            path // path
        );
        uint256 borrowAfter = pair.userBorrowShares(address(this));
        borrowAfter = toAmount(pair, borrowAfter);
        console.log("Borrow delta:", borrowBefore - borrowAfter);
    }

    function test_recoverERC20() public {
        deal(address(stablecoin), address(swapper), 1e18);
        address owner = swapper.owner();
        assertEq(stablecoin.balanceOf(owner), 0);
        vm.prank(owner);
        swapper.recoverERC20(address(stablecoin), 1e18);
        assertEq(stablecoin.balanceOf(address(swapper)), 0);
        assertEq(stablecoin.balanceOf(owner), 1e18);
    }

    function test_UpdateApprovals() public {
        bool canUpdateApprovals = swapper.canUpdateApprovals();
        console.log("Can update approvals:", canUpdateApprovals);
        swapper.updateApprovals();
        address[] memory pairs = registry.getAllPairAddresses();
        assertGt(pairs.length, 0);
        for (uint256 i = 0; i < pairs.length; i++) {
            address _pair = pairs[i];
            address collateral = address(IResupplyPair(_pair).collateral());
            address lifiRouter = swapper.lifiRouter();
            assertGt(IERC20(collateral).allowance(address(swapper), lifiRouter), 1e40);
        }
        assertEq(swapper.canUpdateApprovals(), false);
    }

    function test_RevokeApprovals() public {
        vm.prank(swapper.owner());
        swapper.revokeApprovals();
        address[] memory pairs = registry.getAllPairAddresses();
        assertGt(pairs.length, 0);
        for (uint256 i = 0; i < pairs.length; i++) {
            address _pair = pairs[i];
            address collateral = address(IResupplyPair(_pair).collateral());
            address lifiRouter = swapper.lifiRouter();
            assertEq(IERC20(collateral).allowance(address(swapper), lifiRouter), 0);
        }
        assertEq(IERC20(swapper.reusd()).allowance(address(swapper), swapper.lifiRouter()), 0);
    }

    function test_EncodeDecodePayload() public {
        lifiPayload = LifiApi.getPayload(LifiApi.WETH, LifiApi.USDC, 1e18, 3, address(swapper), address(this));
        lifiPayload = abi.encodePacked(
            lifiPayload,
            "111" // add some extra data to the payload to help test that we are trimming properly
        );
        bytes memory decodedPayload = swapper.decode(swapper.encode(lifiPayload, LifiApi.WETH, LifiApi.USDC));
        assertEq(keccak256(lifiPayload), keccak256(decodedPayload), "Original and decoded payloads don't match");
    }

    // Helper to convert full bytes array to hex string for visual comparison
    function _bytesToFullHex(bytes memory data) internal pure returns (string memory) {
        bytes memory hexBytes = new bytes(2 * data.length + 2);
        hexBytes[0] = "0";
        hexBytes[1] = "x";

        for (uint256 i = 0; i < data.length; i++) {
            uint8 b = uint8(data[i]);
            hexBytes[2 + i * 2] = _hexChar(b / 16);
            hexBytes[3 + i * 2] = _hexChar(b % 16);
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
            if (totalBorrow > 0 && (amount * totalBorrowShares) / totalBorrow < shares) {
                amount = amount + 1;
            }
        }
    }
}
