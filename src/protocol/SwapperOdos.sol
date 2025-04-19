// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { BytesLib } from "solidity-bytes-utils/contracts/BytesLib.sol";
import { CoreOwnable } from "src/dependencies/CoreOwnable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract SwapperOdos is CoreOwnable, ReentrancyGuard {
    using BytesLib for bytes;
    using SafeERC20 for IERC20;

    address public constant odosRouter = 0xCf5540fFFCdC3d510B18bFcA6d2b9987b0772559;
    address public constant registry = 0x10101010E0C3171D894B71B3400668aF311e7D94;

    constructor(address _core) CoreOwnable(_core) {}

    /**
     * @notice Executes a swap through Odos router using an encoded payload in the path parameter
     * @dev This function accepts bytes data encoded as an address[] for compatibility with the legacy interface in PairCore
     */
    function swap(
        address,
        uint256,
        address[] memory _path,
        address
    ) external nonReentrant {
        // Decode the path to get the original Odos router payload
        bytes memory payload = decodeOdosPayload(_path);
        (bool success, bytes memory result) = odosRouter.call{value: 0}(payload);
        require(success, "Odos swap failed");
    }

    function swap(
        address,
        uint256,
        address[] calldata path,
        bytes calldata payload,
        address
    ) external nonReentrant {
        (bool success, bytes memory result) = odosRouter.call{value: 0}(payload);
        require(success, "Odos swap failed");
    }

    function _setApprovals(address[] memory path) internal {
        address registeredPair = IResupplyRegistry(registry).pairsByName(IERC20Metadata(msg.sender).name());
        if(registeredPair != msg.sender) revert();
        address collateral = IResupplyPair(msg.sender).collateral();
        address underlying = IResupplyPair(msg.sender).underlying();
        IERC20(underlying).forceApprove(collateral, type(uint256).max);
    }

    /**
     * @notice Encodes any-length bytes into address[] for transport
     * @param payload The bytes payload to encode
     * @return path The encoded address[]
     */
    function encodeOdosPayload(bytes memory payload) external pure returns (address[] memory path) {
        uint totalLen = payload.length;
        // determine the total number of chunks needed to store the payload
        // each chunk is 20 bytes, so we add 19 to the total length to ensure result is always rounded up
        uint chunkCount = (totalLen + 19) / 20;
        path = new address[](chunkCount + 1); // +1 to store the length prefix which will be needed for decoding

        // Store original payload length in the first address slot (as uint96 in lower 12 bytes)
        path[0] = address(uint160(totalLen)); // packs into the low 20 bytes (safe)

        for (uint i = 0; i < chunkCount; i++) {
            uint offset = i * 20;
            uint end = offset + 20 > totalLen ? totalLen : offset + 20;
            bytes memory chunk = payload.slice(offset, end - offset);

            // Pad to 20 bytes if needed
            if (chunk.length < 20) {
                bytes memory padded = new bytes(20);
                for (uint j = 0; j < chunk.length; j++) {
                    padded[j] = chunk[j];
                }
                chunk = padded;
            }

            path[i + 1] = bytesToAddress(chunk);
        }
    }

    /**
     * @notice Decodes an address array back into its original bytes payload
     * @dev The first address in the path contains the total length of the original payload as a uint96
     * @dev Each subsequent address contains 20 bytes of the original payload
     * @param path The address array containing the encoded payload
     * @return payload The decoded bytes payload
     */
    function decodeOdosPayload(address[] memory path) public pure returns (bytes memory payload) {
        require(path.length > 0, "Empty path");

        uint totalLen = uint(uint160(path[0]));
        
        // Handle all full chunks (all except the last one if it's partial)
        bytes memory fullChunks;
        uint lastIndex = path.length - 1;
        
        // Append all complete chunks using abi.encodePacked
        for (uint i = 1; i < lastIndex; i++) {
            fullChunks = abi.encodePacked(fullChunks, path[i]);
        }
        
        uint remainingBytes = totalLen % 20;
        if (remainingBytes == 0 && path.length > 1) {
            payload = abi.encodePacked(fullChunks, path[lastIndex]);
        } else {
            bytes memory lastChunk = addressToBytes(path[lastIndex]);
            bytes memory trimmedLastChunk = new bytes(remainingBytes);
            for (uint i = 0; i < remainingBytes; i++) {
                trimmedLastChunk[i] = lastChunk[i];
            }
            payload = abi.encodePacked(fullChunks, trimmedLastChunk);
        }
        
        // Ensure the result has the correct length
        require(payload.length == totalLen, "Length mismatch");
    }

    function decodeOdosPayloadOld(address[] memory path) public pure returns (bytes memory payload) {
        require(path.length > 0, "Empty path");

        uint totalLen = uint(uint160(path[0]));
        payload = new bytes(totalLen);

        uint written = 0;
        for (uint i = 1; i < path.length; i++) {
            bytes memory chunk = addressToBytes(path[i]);
            uint toCopy = written + 20 > totalLen ? totalLen - written : 20;
            for (uint j = 0; j < toCopy; j++) {
                payload[written + j] = chunk[j];
            }
            written += toCopy;
        }
    }

    function bytesToAddress(bytes memory b) internal pure returns (address a) {
        require(b.length == 20, "Chunk must be 20 bytes");
        assembly {
            a := mload(add(b, 20))
        }
    }

    function addressToBytes(address a) internal pure returns (bytes memory b) {
        b = new bytes(20);
        assembly {
            mstore(add(b, 32), shl(96, a))
        }
    }
}