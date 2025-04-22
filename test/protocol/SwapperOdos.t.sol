// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { console } from "lib/forge-std/src/console.sol";
import { SwapperOdos } from "src/protocol/SwapperOdos.sol";
import { PairTestBase } from "test/protocol/PairTestBase.t.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { BytesLib } from "solidity-bytes-utils/contracts/BytesLib.sol";
import { OdosApi } from "test/utils/OdosApi.sol";
import { ResupplyPair } from "src/protocol/ResupplyPair.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";

contract SwapperOdosTest is PairTestBase {
    SwapperOdos public swapper;
    address public weth = OdosApi.WETH;
    address public usdc = OdosApi.USDC;
    bytes public odosPayload;
    
    function setUp() public override {
        super.setUp();
        swapper = new SwapperOdos(address(core));
    }

    function test_LiveOdosSwap() public {
        address _core = 0xc07e000044F95655c11fda4cD37F70A94d7e0a7d;
        swapper = new SwapperOdos(_core);
        IResupplyRegistry _registry = IResupplyRegistry(0x10101010E0C3171D894B71B3400668aF311e7D94);
        address _stablecoin = 0x57aB1E0003F623289CD798B1824Be09a793e4Bec;
        address[] memory pairs = _registry.getAllPairAddresses();
        ResupplyPair pair = ResupplyPair(pairs[0]);
        vm.prank(_core);
        pair.setSwapper(address(swapper), true);
        addCollateral(pair, 100_000e18);
        address collateral = address(pair.collateral());

        odosPayload = OdosApi.getPayload(
            _stablecoin,
            collateral, 
            1e18,   // amount
            3,      // slippage pct
            address(this)
        );

        address[] memory path = swapper.encode(odosPayload);

        console.log("Odos payload:", _bytesToFullHex(odosPayload));

        pair.leveragedPosition(
            address(swapper), 
            1_000e18, // borrow amount
            1e18, // initial collateral amount
            1e18, // amount collateral out min
            path // encoded path
        );
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
        for (uint i = 0; i < pairs.length; i++) {
            address pair = pairs[i];
            address collateral = address(ResupplyPair(pair).collateral());
            address odosRouter = swapper.odosRouter();
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
            address pair = pairs[i];
            address collateral = address(ResupplyPair(pair).collateral());
            address odosRouter = swapper.odosRouter();
            assertEq(IERC20(collateral).allowance(address(swapper), odosRouter), 0);
        }
        assertEq(IERC20(swapper.reusd()).allowance(address(swapper), swapper.odosRouter()), 0);
    }

    function test_EncodeDecodePayload() public {
        // At time of writing tests, our collateral tokens are not yet supported by Odos, so we use WETH/USDC for testing
        deal(weth, address(swapper), 100e18);
        vm.prank(address(swapper));
        IERC20(weth).approve(swapper.odosRouter(), type(uint256).max);
        odosPayload = OdosApi.getPayloadForWethToUsdc(1e18, 3, address(this));
        odosPayload = abi.encodePacked(
            odosPayload,
            "111" // add some extra data to the payload to help test that we are trimming properly
        );
        console.log("Original payload:", _bytesToFullHex(odosPayload));
        
        address[] memory encodedPath = swapper.encode(odosPayload); // Encode to path array
        uint256 originalLength = uint160(encodedPath[0]); // Length is stored in the second element
        bytes memory decodedPayload;
        uint lastIndex = encodedPath.length - 1;
        for (uint i = 1; i < lastIndex; i++) {
            console.log("Appending element:", i, _bytesToFullHex(abi.encodePacked(encodedPath[i])));
            decodedPayload = abi.encodePacked(decodedPayload, encodedPath[i]);
        }
        // Use our length value to find and trim any extra padding that was added to the final element
        bytes memory trimmedFinalElement = BytesLib.slice(
            abi.encodePacked(encodedPath[lastIndex]),
            0,
            originalLength % 20
        );
        console.log("Appending element:", lastIndex, _bytesToFullHex(trimmedFinalElement));
        decodedPayload = abi.encodePacked(decodedPayload, trimmedFinalElement);
        console.log("Original payload:", _bytesToFullHex(odosPayload));
        console.log("Decoded payload:", _bytesToFullHex(decodedPayload));
        
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
}