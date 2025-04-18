// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {OdosSwapper} from "src/protocol/OdosSwapper.sol";
import { PairTestBase } from "test/protocol/PairTestBase.t.sol";
contract OdosSwapperTest is PairTestBase {
    OdosSwapper public swapper;
    
    function setUp() public override {
        super.setUp();
        swapper = new OdosSwapper(address(core), address(this));
    }
    
    // Helper to log direct comparison between original and decoded bytes
    function _logComparisonSample(bytes memory original, bytes memory decoded) internal {
        uint len = original.length;
        require(len == decoded.length, "Length mismatch");
        
        // Compare first 20 bytes
        for (uint i = 0; i < 20 && i < len; i++) {
            bytes1 origByte = original[i];
            bytes1 decodedByte = decoded[i];
            bool isMatch = origByte == decodedByte;
            string memory matchSymbol;
            if (isMatch) {
                matchSymbol = " [MATCH]";
            } else {
                matchSymbol = " [DIFF]";
            }
        }
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
    
    function test_EncodeDecodeApiPayload() public {
        // The Odos API payload provided
        bytes memory originalPayload = hex"83bd37f900012260fac5e5542a773aa44fbcfedf7c193bc2c5990001c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2040b43e94009057cd21d6aafe3400000c49b0001fb2139331532e3ee59777FBbcB14aF674f3fd6710000000147E2D28169738039755586743E2dfCF3bd643f860000000003010203002701010102ff000000000000000000000000000000000000000000002260fac5e5542a773aa44fbcfedf7c193bc2c599c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000000000";
        
        // Log original bytes as full hex
        console.log("Original payload (full hex):");
        console.log(_bytesToFullHex(originalPayload));
        console.log("Original payload length:", originalPayload.length);
        
        // Encode the payload to address[]
        address[] memory encoded = swapper.encodeOdosPayload(originalPayload);
        
        // Log encoded array info
        console.log("Encoded array length:", encoded.length);
        console.log("Length stored in first address:", uint(uint160(encoded[0])));
        
        // Decode back to bytes
        bytes memory decoded = swapper.decodeOdosPayload(encoded);
        
        // Log decoded bytes as full hex
        console.log("Decoded payload (full hex):");
        console.log(_bytesToFullHex(decoded));
        console.log("Decoded payload length:", decoded.length);
        
        // Verify the full comparison
        _logComparisonSample(originalPayload, decoded);
        
        // Compare hashes
        bytes32 originalHash = keccak256(originalPayload);
        bytes32 decodedHash = keccak256(decoded);
        console.log("Original hash:", uint256(originalHash));
        console.log("Decoded hash:", uint256(decodedHash));
        console.log("Hashes match:", originalHash == decodedHash ? "Yes" : "No");
        
        // Run assertions to confirm
        assertEq(decoded.length, originalPayload.length, "Length mismatch");
        assertEq(originalHash, decodedHash, "Hash mismatch");
    }
    
    function test_VariableLengthPayloads() public {
        // Test empty payload
        bytes memory emptyPayload = new bytes(0);
        address[] memory emptyEncoded = swapper.encodeOdosPayload(emptyPayload);
        bytes memory emptyDecoded = swapper.decodeOdosPayload(emptyEncoded);
        assertEq(emptyDecoded.length, 0, "Empty payload should decode to empty bytes");
        
        // Test various payload sizes to ensure robust handling
        test_PayloadSize(1);     // 1 byte (smallest non-empty)
        test_PayloadSize(19);    // Just under 1 chunk
        test_PayloadSize(20);    // Exactly 1 chunk
        test_PayloadSize(21);    // Just over 1 chunk
        test_PayloadSize(39);    // Just under 2 chunks
        test_PayloadSize(40);    // Exactly 2 chunks
        test_PayloadSize(100);   // Arbitrary medium size
        test_PayloadSize(1000);  // Large payload
    }
    
    function test_PayloadSize(uint size) internal {
        // Create payload with specified size filled with incrementing values
        bytes memory payload = new bytes(size);
        for (uint i = 0; i < size; i++) {
            payload[i] = bytes1(uint8(i % 256));
        }
        
        // Encode and decode
        address[] memory encoded = swapper.encodeOdosPayload(payload);
        bytes memory decoded = swapper.decodeOdosPayload(encoded);
        
        // Verify size and content
        assertEq(decoded.length, size, "Decoded length doesn't match for size");
        
        for (uint i = 0; i < size; i++) {
            assertEq(decoded[i], payload[i], string(abi.encodePacked("Byte mismatch at index ", vm.toString(i), " for size ", vm.toString(size))));
        }
    }
    
    function test_EdgeCasesAndBoundaries() public {
        // Test with payload containing all zeros
        bytes memory allZeros = new bytes(100);
        address[] memory zerosEncoded = swapper.encodeOdosPayload(allZeros);
        bytes memory zerosDecoded = swapper.decodeOdosPayload(zerosEncoded);
        assertEq(keccak256(zerosDecoded), keccak256(allZeros), "All zeros payload failed");
        
        // Test with payload containing all ones (0xFF)
        bytes memory allOnes = new bytes(100);
        for (uint i = 0; i < 100; i++) {
            allOnes[i] = 0xFF;
        }
        address[] memory onesEncoded = swapper.encodeOdosPayload(allOnes);
        bytes memory onesDecoded = swapper.decodeOdosPayload(onesEncoded);
        assertEq(keccak256(onesDecoded), keccak256(allOnes), "All ones payload failed");
        
        // Test with payload containing a mix of values at boundaries
        bytes memory mixed = new bytes(40);
        mixed[0] = 0x00;            // First byte - minimum
        mixed[19] = 0xFF;           // Last byte of first chunk - maximum
        mixed[20] = 0x80;           // First byte of second chunk - midpoint
        mixed[39] = 0x7F;           // Last byte - random value
        
        address[] memory mixedEncoded = swapper.encodeOdosPayload(mixed);
        bytes memory mixedDecoded = swapper.decodeOdosPayload(mixedEncoded);
        
        assertEq(mixedDecoded[0], mixed[0], "First byte mismatch");
        assertEq(mixedDecoded[19], mixed[19], "Chunk boundary byte mismatch");
        assertEq(mixedDecoded[20], mixed[20], "Chunk start byte mismatch");
        assertEq(mixedDecoded[39], mixed[39], "Last byte mismatch");
    }
}
