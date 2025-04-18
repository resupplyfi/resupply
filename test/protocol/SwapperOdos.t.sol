// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// import "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { SwapperOdos } from "src/protocol/SwapperOdos.sol";
import { PairTestBase } from "test/protocol/PairTestBase.t.sol";

contract SwapperOdosTest is PairTestBase {
    SwapperOdos public swapper;
    
    function setUp() public override {
        super.setUp();
        swapper = new SwapperOdos(address(core), address(this));
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
        console.log("Original payload length:");
        console.log(originalPayload.length);
        
        // Encode the payload to address[]
        address[] memory encoded = swapper.encodeOdosPayload(originalPayload);
        
        // Log encoded array info
        console.log("Encoded array length:");
        console.log(encoded.length);
        console.log("Length stored in first address:");
        console.log(uint(uint160(encoded[0])));
        
        // Decode back to bytes
        bytes memory decoded = swapper.decodeOdosPayload(encoded);
        
        // Log decoded bytes as full hex
        console.log("Decoded payload (full hex):");
        console.log(_bytesToFullHex(decoded));
        console.log("Decoded payload length:");
        console.log(decoded.length);
        
        // Verify the full comparison
        _logComparisonSample(originalPayload, decoded);
        
        // Compare hashes
        bytes32 originalHash = keccak256(originalPayload);
        bytes32 decodedHash = keccak256(decoded);
        console.log("Original hash:");
        console.log(uint256(originalHash));
        console.log("Decoded hash:");
        console.log(uint256(decodedHash));
        console.log("Hashes match:");
        if (originalHash == decodedHash) {
            console.log("Yes");
        } else {
            console.log("No");
        }
        
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
    
    function test_GasMeasurement() public {
        // Create payloads of different sizes to test gas usage
        bytes[] memory payloads = new bytes[](4);
        payloads[0] = new bytes(20);   // Exactly 1 chunk
        payloads[1] = new bytes(100);  // 5 chunks
        payloads[2] = new bytes(200);  // 10 chunks
        payloads[3] = hex"83bd37f900012260fac5e5542a773aa44fbcfedf7c193bc2c5990001c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2040b43e94009057cd21d6aafe3400000c49b0001fb2139331532e3ee59777FBbcB14aF674f3fd6710000000147E2D28169738039755586743E2dfCF3bd643f860000000003010203002701010102ff000000000000000000000000000000000000000000002260fac5e5542a773aa44fbcfedf7c193bc2c599c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000000000"; // Real Odos payload
        
        // Fill with random-like data
        for (uint i = 0; i < payloads[0].length; i++) {
            payloads[0][i] = bytes1(uint8(i % 256));
        }
        for (uint i = 0; i < payloads[1].length; i++) {
            payloads[1][i] = bytes1(uint8(i % 256));
        }
        for (uint i = 0; i < payloads[2].length; i++) {
            payloads[2][i] = bytes1(uint8(i % 256));
        }
        
        // Test labels for readability
        string[] memory labels = new string[](4);
        labels[0] = "20 bytes (1 chunk)";
        labels[1] = "100 bytes (5 chunks)";
        labels[2] = "200 bytes (10 chunks)";
        labels[3] = "Odos API payload";
        
        console.log("=== GAS MEASUREMENT RESULTS ===");
        console.log("All gas numbers in units of gas");
        
        // Measure gas for all payloads
        for (uint i = 0; i < payloads.length; i++) {
            bytes memory payload = payloads[i];
            uint256 size = payload.length;
            uint256 chunks = (size + 19) / 20;
            
            console.log("\n----- Testing", labels[i], "-----");
            console.log("Payload size:", size, "bytes");
            console.log("Required chunks:", chunks);
            
            // Measure encoding gas
            uint256 gasBefore = gasleft();
            address[] memory encoded = swapper.encodeOdosPayload(payload);
            uint256 encodeGas = gasBefore - gasleft();
            
            console.log("Gas used for encoding:", encodeGas);
            console.log("Gas per byte for encoding:", encodeGas / size);
            
            // Measure decoding gas
            gasBefore = gasleft();
            bytes memory decoded = swapper.decodeOdosPayload(encoded);
            uint256 decodeGas = gasBefore - gasleft();
            
            console.log("Gas used for decoding:", decodeGas);
            console.log("Gas per byte for decoding:", decodeGas / size);
            console.log("Total gas (encode + decode):", encodeGas + decodeGas);
            
            // Verify correctness
            bytes32 originalHash = keccak256(payload);
            bytes32 decodedHash = keccak256(decoded);
            bool hashesMatch = originalHash == decodedHash;
            console.log("Hashes match:", hashesMatch ? "Yes" : "No");
            
            assert(hashesMatch);
        }
    }
    
    function test_SwapFunctionGas() public {
        // The actual Odos API payload for testing
        bytes memory odosPayload = hex"83bd37f900012260fac5e5542a773aa44fbcfedf7c193bc2c5990001c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2040b43e94009057cd21d6aafe3400000c49b0001fb2139331532e3ee59777FBbcB14aF674f3fd6710000000147E2D28169738039755586743E2dfCF3bd643f860000000003010203002701010102ff000000000000000000000000000000000000000000002260fac5e5542a773aa44fbcfedf7c193bc2c599c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000000000";
        
        // First encode the payload
        address[] memory encodedPath = swapper.encodeOdosPayload(odosPayload);
        
        // Mock the odosRouter to prevent the external call
        MockOdosRouter mockRouter = new MockOdosRouter();
        vm.prank(swapper.owner());
        swapper.setOdosRouter(address(mockRouter));
        
        console.log("\n=== SWAP FUNCTION GAS ANALYSIS ===");
        console.log("Measuring gas for entire swap function with payload size:", odosPayload.length, "bytes");
        
        // Snapshot gas for swap measurement
        uint256 gasBefore = gasleft();
        
        // Call the swap function
        swapper.swap(address(this), 0, encodedPath, address(this));
        
        // Calculate gas used
        uint256 swapGas = gasBefore - gasleft();
        
        console.log("Total gas used for swap:", swapGas);
        console.log("Gas per byte:", swapGas / odosPayload.length);
        
        // Check if the payload was correctly received by the mock router
        bytes memory receivedPayload = mockRouter.lastPayload();
        console.log("Original payload length:", odosPayload.length);
        console.log("Received payload length:", receivedPayload.length);
        
        // Verify the payload was decoded correctly
        bytes32 originalHash = keccak256(odosPayload);
        bytes32 receivedHash = keccak256(receivedPayload);
        bool hashesMatch = originalHash == receivedHash;
        console.log("Payload hashes match:", hashesMatch ? "Yes" : "No");
        
        assert(hashesMatch);
    }
    
    function test_DecodeGasAnalysis() public {
        console.log("\n=== DETAILED DECODE GAS ANALYSIS ===");
        
        // Create a range of payload sizes to analyze gas scaling
        uint256[] memory sizes = new uint256[](8);
        sizes[0] = 20;    // 1 chunk
        sizes[1] = 40;    // 2 chunks
        sizes[2] = 60;    // 3 chunks
        sizes[3] = 100;   // 5 chunks
        sizes[4] = 200;   // 10 chunks
        sizes[5] = 400;   // 20 chunks
        sizes[6] = 600;   // 30 chunks
        sizes[7] = 800;   // 40 chunks
        
        // For each size, create a payload, encode it, and measure decode gas
        for (uint i = 0; i < sizes.length; i++) {
            uint256 size = sizes[i];
            uint256 chunks = (size + 19) / 20;
            
            // Create and fill test payload
            bytes memory payload = new bytes(size);
            for (uint j = 0; j < size; j++) {
                payload[j] = bytes1(uint8(j % 256));
            }
            
            // Encode it
            address[] memory encoded = swapper.encodeOdosPayload(payload);
            
            // Measure decode gas
            uint256 gasBefore = gasleft();
            bytes memory decoded = swapper.decodeOdosPayload(encoded);
            uint256 decodeGas = gasBefore - gasleft();
            
            // Log results
            console.log(string.concat("Size: ", vm.toString(size), " bytes (", vm.toString(chunks), " chunks)"));
            console.log("  Decode gas:", decodeGas);
            console.log("  Gas per byte:", decodeGas / size);
            console.log("  Gas per chunk:", decodeGas / chunks);
            
            // Quick sanity check
            assertEq(keccak256(payload), keccak256(decoded), "Decode failed");
        }
        
        // Analyze the real Odos payload
        bytes memory odosPayload = hex"83bd37f900012260fac5e5542a773aa44fbcfedf7c193bc2c5990001c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2040b43e94009057cd21d6aafe3400000c49b0001fb2139331532e3ee59777FBbcB14aF674f3fd6710000000147E2D28169738039755586743E2dfCF3bd643f860000000003010203002701010102ff000000000000000000000000000000000000000000002260fac5e5542a773aa44fbcfedf7c193bc2c599c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000000000";
        uint256 odosSize = odosPayload.length;
        uint256 odosChunks = (odosSize + 19) / 20;
        
        address[] memory odosEncoded = swapper.encodeOdosPayload(odosPayload);
        
        uint256 gasBefore = gasleft();
        bytes memory odosDecoded = swapper.decodeOdosPayload(odosEncoded);
        uint256 odosDecodeGas = gasBefore - gasleft();
        
        console.log("\nOdos API Payload:");
        console.log("  Size:", odosSize, "bytes");
        console.log("  Chunks:", odosChunks);
        console.log("  Decode gas:", odosDecodeGas);
        console.log("  Gas per byte:", odosDecodeGas / odosSize);
        console.log("  Gas per chunk:", odosDecodeGas / odosChunks);
    }
    
    function test_SimpleDecodeGasMeasurement() public {
        // Create a real Odos payload for testing
        bytes memory odosPayload = hex"83bd37f900012260fac5e5542a773aa44fbcfedf7c193bc2c5990001c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2040b43e94009057cd21d6aafe3400000c49b0001fb2139331532e3ee59777FBbcB14aF674f3fd6710000000147E2D28169738039755586743E2dfCF3bd643f860000000003010203002701010102ff000000000000000000000000000000000000000000002260fac5e5542a773aa44fbcfedf7c193bc2c599c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000000000";
        
        console.log("==========================================");
        console.log("     SIMPLE DECODE GAS MEASUREMENT");
        console.log("==========================================");
        
        // STEP 1: Encode the payload first
        address[] memory encoded = swapper.encodeOdosPayload(odosPayload);
        
        // STEP 2: Measure gas for decoding only
        console.log("PAYLOAD SIZE:");
        console.log(vm.toString(odosPayload.length));
        
        // Warmup call to avoid first-call anomalies
        bytes memory warmup = swapper.decodeOdosPayload(encoded);
        require(warmup.length == odosPayload.length, "Warmup failed");
        
        // Actual gas measurement
        uint256 startGas = gasleft();
        bytes memory decoded = swapper.decodeOdosPayload(encoded);
        uint256 gasUsed = startGas - gasleft();
        
        console.log("DECODE GAS:");
        console.log(vm.toString(gasUsed));
        
        console.log("GAS PER BYTE:");
        console.log(vm.toString(gasUsed / odosPayload.length));
        
        // STEP 3: Verify correctness
        bool hashes_match = keccak256(decoded) == keccak256(odosPayload);
        require(hashes_match, "Hashes don't match");
        
        // STEP 4: Measure a single swap (which includes decode)
        MockOdosRouter mockRouter = new MockOdosRouter();
        vm.prank(swapper.owner());
        swapper.setOdosRouter(address(mockRouter));
        
        startGas = gasleft();
        swapper.swap(address(this), 0, encoded, address(this));
        uint256 swapGas = startGas - gasleft();
        
        console.log("SWAP TOTAL GAS:");
        console.log(vm.toString(swapGas));
        
        uint256 overhead = swapGas - gasUsed;
        console.log("SWAP OVERHEAD BEYOND DECODE:");
        console.log(vm.toString(overhead));
        
        console.log("==========================================");
    }
    
    function test_BasicGasNumbers() public {
        // Create payloads of specific sizes for testing
        bytes memory smallPayload = new bytes(20);  // 1 chunk
        bytes memory mediumPayload = new bytes(200); // 10 chunks
        bytes memory largePayload = hex"83bd37f900012260fac5e5542a773aa44fbcfedf7c193bc2c5990001c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2040b43e94009057cd21d6aafe3400000c49b0001fb2139331532e3ee59777FBbcB14aF674f3fd6710000000147E2D28169738039755586743E2dfCF3bd643f860000000003010203002701010102ff000000000000000000000000000000000000000000002260fac5e5542a773aa44fbcfedf7c193bc2c599c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000000000";
        
        // Fill with random data
        for (uint i = 0; i < smallPayload.length; i++) {
            smallPayload[i] = bytes1(uint8(i % 256));
        }
        for (uint i = 0; i < mediumPayload.length; i++) {
            mediumPayload[i] = bytes1(uint8(i % 256));
        }
        
        // Encode payloads first
        address[] memory smallEncoded = swapper.encodeOdosPayload(smallPayload);
        address[] memory mediumEncoded = swapper.encodeOdosPayload(mediumPayload);
        address[] memory largeEncoded = swapper.encodeOdosPayload(largePayload);
        
        // Create a mock router for swap tests
        MockOdosRouter mockRouter = new MockOdosRouter();
        vm.prank(swapper.owner());
        swapper.setOdosRouter(address(mockRouter));
        
        console.log("=============================================");
        console.log("             GAS USAGE ANALYSIS             ");
        console.log("=============================================");
        
        // Warmup to avoid first-call gas anomalies
        swapper.decodeOdosPayload(smallEncoded);
        
        // Test small payload decode (1 chunk)
        uint256 gas1 = gasleft();
        swapper.decodeOdosPayload(smallEncoded);
        uint256 smallDecodeGas = gas1 - gasleft();
        
        // Need to convert uint256 to string for console.log
        string memory smallDecodeGasStr = vm.toString(smallDecodeGas);
        console.log("DECODE 20 bytes (1 chunk):");
        console.log(smallDecodeGasStr);
        
        // Test medium payload decode (10 chunks)
        gas1 = gasleft();
        swapper.decodeOdosPayload(mediumEncoded);
        uint256 mediumDecodeGas = gas1 - gasleft();
        
        string memory mediumDecodeGasStr = vm.toString(mediumDecodeGas);
        console.log("DECODE 200 bytes (10 chunks):");
        console.log(mediumDecodeGasStr);
        
        // Test large payload decode (real Odos payload)
        gas1 = gasleft();
        swapper.decodeOdosPayload(largeEncoded);
        uint256 largeDecodeGas = gas1 - gasleft();
        
        string memory largeDecodeGasStr = vm.toString(largeDecodeGas);
        console.log("DECODE Odos payload (", vm.toString(largePayload.length), " bytes):");
        console.log(largeDecodeGasStr);
        
        // Test swap with small payload
        gas1 = gasleft();
        swapper.swap(address(this), 0, smallEncoded, address(this));
        uint256 smallSwapGas = gas1 - gasleft();
        
        string memory smallSwapGasStr = vm.toString(smallSwapGas);
        console.log("SWAP with 20 bytes:");
        console.log(smallSwapGasStr);
        
        // Test swap with large payload
        gas1 = gasleft();
        swapper.swap(address(this), 0, largeEncoded, address(this));
        uint256 largeSwapGas = gas1 - gasleft();
        
        string memory largeSwapGasStr = vm.toString(largeSwapGas);
        console.log("SWAP with Odos payload:");
        console.log(largeSwapGasStr);
        
        // Calculate gas per byte
        console.log("Gas per byte (small):");
        console.log(vm.toString(smallDecodeGas / 20));
        
        console.log("Gas per byte (medium):");
        console.log(vm.toString(mediumDecodeGas / 200));
        
        console.log("Gas per byte (large):");
        console.log(vm.toString(largeDecodeGas / largePayload.length));
        
        console.log("Decode overhead beyond small payload (large - small):");
        console.log(vm.toString(largeDecodeGas - smallDecodeGas));
        
        console.log("=============================================");
    }
    
    // Helper function to measure just the decode gas in isolation
    function measureDecodeGas(address[] memory encoded) internal returns (uint256) {
        uint256 startGas = gasleft();
        swapper.decodeOdosPayload(encoded);
        return startGas - gasleft();
    }
    
    // Helper function to measure swap gas in isolation
    function measureSwapGas(address[] memory encoded) internal returns (uint256) {
        uint256 startGas = gasleft();
        swapper.swap(address(this), 0, encoded, address(this));
        return startGas - gasleft();
    }
}

// Mock Odos Router for testing swap function gas
contract MockOdosRouter {
    bytes public lastPayload;
    
    // Fallback function to capture the payload
    fallback() external payable {
        lastPayload = msg.data;
    }
    
    // Receive function for ETH transfers
    receive() external payable {}
}
