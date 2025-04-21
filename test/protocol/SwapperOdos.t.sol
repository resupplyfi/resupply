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
    
    // Store the Odos payload once and reuse it for all tests
    bytes public odosPayload;
    
    function setUp() public override {
        super.setUp();
        swapper = new SwapperOdos(address(core));
        deal(weth, address(swapper), 100e18);
        
        // Ensure swapper contract has approval to spend tokens
        vm.prank(address(swapper));
        IERC20(weth).approve(swapper.odosRouter(), type(uint256).max);
        
        // Get Odos payload once and store it for all tests
        console.log("Fetching Odos payload during setup...");
        
        // Fetch the real payload for swapping WETH to USDC
        odosPayload = OdosApi.getPayloadForWethToUsdc(1e18, 3, address(this));
        
        console.log("Setup complete, payload length:", odosPayload.length);
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

    function test_EncodeDecodePayload() public {
        // add some extra data to the payload to help test that we are trimming properly
        odosPayload = abi.encodePacked(
            odosPayload,
            "111"
        );
        console.log("Original payload:", _bytesToFullHex(odosPayload));
        
        // now lets encode into an array of addresses
        address[] memory encodedPath = swapper.encode(odosPayload);

        // Length is stored in the second element
        uint256 originalLength = uint160(encodedPath[0]);
        
        console.log("Original length stored in first element:", originalLength);
        
        // Loop through the encoded path, appending each element to `decodedPayload`
        bytes memory decodedPayload;
        uint lastIndex = encodedPath.length - 1;
        for (uint i = 1; i < lastIndex; i++) {
            console.log("Appending element:", i, _bytesToFullHex(abi.encodePacked(encodedPath[i])));
            decodedPayload = abi.encodePacked(decodedPayload, encodedPath[i]);
        }
        // Trim any extra padding that was added to the final element
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