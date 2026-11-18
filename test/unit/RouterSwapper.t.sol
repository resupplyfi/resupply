// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Protocol } from "src/Constants.sol";
import { RouterSwapper } from "src/protocol/swappers/RouterSwapper.sol";

contract RecordingRouter {
    bytes32 public payloadHash;

    fallback() external {
        payloadHash = keccak256(msg.data);
    }
}

contract RouterSwapperTest is Test {
    RouterSwapper internal swapper;
    RecordingRouter internal router;

    function setUp() public {
        vm.mockCall(Protocol.STABLECOIN, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
        router = new RecordingRouter();
        swapper = new RouterSwapper(Protocol.CORE, address(router), "Test swapper");
    }

    function test_DecodeChunkAndWordBoundaries() public view {
        // Cover every alignment of the 20-byte chunks against 32-byte memory words.
        for (uint256 length = 1; length <= 161; length++) {
            _assertDecoded(_payload(length, 247));
        }
    }

    function testFuzz_DecodeMatchesPayload(uint16 length, uint8 seed) public view {
        _assertDecoded(_payload(bound(length, 1, 4096), seed));
    }

    function test_EncodeDecodeRoundTrip() public view {
        bytes memory payload = _payload(1021, 19);
        address[] memory path = swapper.encode(payload, address(1), address(2));
        assertEq(path[0], address(1));
        assertEq(path[path.length - 1], address(2));
        assertEq(swapper.decode(path), payload);
    }

    function test_DecodeRejectsMalformedLengths() public {
        for (uint256 length; length < 3; length++) {
            vm.expectRevert("Invalid path");
            swapper.decode(new address[](length));
        }

        address[] memory path = _path(hex"123456");
        uint160[3] memory invalidLengths = [uint160(0), 21, type(uint160).max];
        for (uint256 i; i < invalidLengths.length; i++) {
            path[1] = address(invalidLengths[i]);
            vm.expectRevert("Length mismatch");
            swapper.decode(path);
        }

        path = new address[](5);
        path[1] = address(3); // Too many chunks for the declared length.
        vm.expectRevert("Length mismatch");
        swapper.decode(path);

        path = new address[](3);
        path[1] = address(1); // No payload chunk; legacy decoding read the length field.
        vm.expectRevert("Length mismatch");
        swapper.decode(path);

        path = swapper.encode("", address(1), address(2));
        vm.expectRevert("Length mismatch");
        swapper.decode(path);
    }

    function test_LargePayloadsReachRouterWithinGasBudget() public {
        uint256[2] memory lengths = [uint256(14_600), 30_000];
        for (uint256 i; i < lengths.length; i++) {
            bytes memory payload = _payload(lengths[i], 71);
            address[] memory path = _path(payload);
            // The old decoder alone consumes >50M gas at 14.6 kB.
            (bool success,) = address(swapper).call{ gas: 2_000_000 }(abi.encodeCall(RouterSwapper.swap, (address(this), 0, path, address(this))));
            assertTrue(success, "large route exceeds gas budget");
            assertEq(router.payloadHash(), keccak256(payload), "router received different calldata");
        }
    }

    function _assertDecoded(bytes memory payload) internal view {
        (bool success, bytes memory result) = address(swapper).staticcall(abi.encodeCall(RouterSwapper.decode, (_path(payload))));
        assertTrue(success);
        // Also check canonical ABI padding, not just the logical payload bytes.
        assertEq(result, abi.encode(payload));
    }

    function _payload(uint256 length, uint8 seed) internal pure returns (bytes memory payload) {
        payload = new bytes(length);
        for (uint256 i; i < length; i++) {
            payload[i] = bytes1(uint8(i * 17 + seed));
        }
    }

    function _path(bytes memory payload) internal pure returns (address[] memory path) {
        uint256 chunks = (payload.length + 19) / 20;
        path = new address[](chunks + 3);
        path[0] = address(1);
        path[1] = address(uint160(payload.length));
        path[path.length - 1] = address(2);
        // Build independently of encode(), with nonzero padding that decode must ignore.
        for (uint256 i; i < chunks; i++) {
            uint160 chunk;
            for (uint256 j; j < 20; j++) {
                uint256 offset = i * 20 + j;
                chunk = (chunk << 8) | uint160(offset < payload.length ? uint8(payload[offset]) : 0xff);
            }
            path[i + 2] = address(chunk);
        }
    }
}
