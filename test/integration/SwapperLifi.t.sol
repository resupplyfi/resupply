// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { console } from "lib/forge-std/src/console.sol";
import { RouterSwapper } from "src/protocol/swappers/RouterSwapper.sol";
import { PairTestBase } from "test/integration/PairTestBase.t.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "src/interfaces/IERC4626.sol";
import { LifiApi } from "test/utils/LifiApi.sol";

contract SwapperLifiTest is PairTestBase {
    RouterSwapper public swapper;
    bytes public lifiPayload;

    function setUp() public override {
        super.setUp();
        swapper = new RouterSwapper(address(core), LifiApi.LIFI_ROUTER, "Resupply Swapper: LI.FI");
    }

    function test_Name() public view {
        assertEq(swapper.name(), "Resupply Swapper: LI.FI");
    }

    function test_Router() public view {
        assertEq(swapper.router(), LifiApi.LIFI_ROUTER);
    }

    function test_LiveLifiSwap() public {
        uint256 amountIn = 1_000e18;
        deal(address(stablecoin), address(swapper), amountIn);

        LifiApi.Quote memory lifiQuote = LifiApi.getQuote(
            address(stablecoin),
            LifiApi.USDC,
            amountIn,
            3,
            address(swapper),
            address(this)
        );
        assertGt(lifiQuote.payload.length, 0, "API returned empty payload");
        assertGt(lifiQuote.amountOutMin, 0, "API returned zero minimum output");

        address[] memory path = swapper.encode(lifiQuote.payload, address(stablecoin), LifiApi.USDC);
        uint256 balanceBefore = IERC20(LifiApi.USDC).balanceOf(address(this));
        swapper.swap(address(this), amountIn, path, address(this));
        uint256 balanceDelta = IERC20(LifiApi.USDC).balanceOf(address(this)) - balanceBefore;
        assertGe(balanceDelta, lifiQuote.amountOutMin, "insufficient USDC out");
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
        for (uint256 i = 0; i < pairs.length; i++) {
            address _pair = pairs[i];
            address collateral = address(IResupplyPair(_pair).collateral());
            address lifiRouter = swapper.router();
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
            address lifiRouter = swapper.router();
            assertEq(IERC20(collateral).allowance(address(swapper), lifiRouter), 0);
        }
        assertEq(IERC20(swapper.reusd()).allowance(address(swapper), swapper.router()), 0);
        vm.expectRevert("approvals revoked");
        swapper.swap(address(this), 0, new address[](0), address(this));
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
