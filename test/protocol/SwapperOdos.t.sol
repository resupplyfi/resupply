// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// import "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { SwapperOdos } from "src/protocol/SwapperOdos.sol";
import { PairTestBase } from "test/protocol/PairTestBase.t.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SwapperOdosTest is PairTestBase {
    SwapperOdos public swapper;
    address public weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    
    // Store the Odos payload once and reuse it for all tests
    bytes public odosPayload;
    address[] public encodedPath;
    
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
        // This function will fall back to the hardcoded payload if API call fails
        odosPayload = getOdosPayloadForWethToUsdc(1e18, 3);
        
        // Pre-encode the path for efficiency
        encodedPath = swapper.encodeOdosPayload(odosPayload);
        
        console.log("Setup complete, payload length:", odosPayload.length);
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
        // Use the stored payload
        bytes memory originalPayload = odosPayload;
        
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
    
    /**
     * @notice Test that only focuses on gas measurements of encoding/decoding
     */
    function test_EncodingDecodingGas() public {
        console.log("\n=== ENCODING/DECODING GAS ANALYSIS ===");
        console.log("Payload size:", odosPayload.length, "bytes");
        
        // Measure encoding gas
        uint256 encodeStart = gasleft();
        address[] memory encoded = swapper.encodeOdosPayload(odosPayload);
        uint256 encodeGas = encodeStart - gasleft();
        
        console.log("Gas used for encoding:", encodeGas);
        if (odosPayload.length > 0) {
            console.log("Gas per byte for encoding:", encodeGas / odosPayload.length);
        }
        
        // Measure decoding gas
        uint256 decodeStart = gasleft();
        bytes memory decoded = swapper.decodeOdosPayload(encodedPath);
        uint256 decodeGas = decodeStart - gasleft();
        
        console.log("Gas used for decoding:", decodeGas);
        if (odosPayload.length > 0) {
            console.log("Gas per byte for decoding:", decodeGas / odosPayload.length);
        }
        console.log("Total gas (encode + decode):", encodeGas + decodeGas);
        
        // Verify correctness
        bytes32 originalHash = keccak256(odosPayload);
        bytes32 decodedHash = keccak256(decoded);
        bool hashesMatch = originalHash == decodedHash;
        console.log("Hashes match:", hashesMatch ? "Yes" : "No");
        
        assert(hashesMatch);
    }
    
    /**
     * @notice Test varying sizes of payloads to see how gas scales
     */
    function test_PayloadSizeScaling() public {
        console.log("\n=== PAYLOAD SIZE SCALING ===");
        
        uint256[] memory sizes = new uint256[](5);
        sizes[0] = 20;    // 1 chunk
        sizes[1] = 100;   // 5 chunks
        sizes[2] = 200;   // 10 chunks
        sizes[3] = 400;   // 20 chunks
        sizes[4] = 800;   // 40 chunks
        
        for (uint i = 0; i < sizes.length; i++) {
            uint256 size = sizes[i];
            bytes memory payload = new bytes(size);
            for (uint j = 0; j < size; j++) {
                payload[j] = bytes1(uint8(j % 256));
            }
            
            uint256 encodeStart = gasleft();
            address[] memory encoded = swapper.encodeOdosPayload(payload);
            uint256 encodeGas = encodeStart - gasleft();
            
            uint256 decodeStart = gasleft();
            bytes memory decoded = swapper.decodeOdosPayload(encoded);
            uint256 decodeGas = decodeStart - gasleft();
            
            console.log("Size:", size, "bytes");
            console.log("  Encode gas:", encodeGas);
            console.log("  Decode gas:", decodeGas);
            console.log("  Total gas:", encodeGas + decodeGas);
            if (size > 0) {
                console.log("  Gas per byte:", (encodeGas + decodeGas) / size);
            }
            
            // Verify correctness
            assertEq(keccak256(payload), keccak256(decoded), "Hash mismatch");
        }
        
        // Also test with our stored Odos payload
        uint256 encodeStart = gasleft();
        address[] memory encoded = swapper.encodeOdosPayload(odosPayload);
        uint256 encodeGas = encodeStart - gasleft();
        
        uint256 decodeStart = gasleft();
        bytes memory decoded = swapper.decodeOdosPayload(encoded);
        uint256 decodeGas = decodeStart - gasleft();
        
        console.log("\nOdos payload size:", odosPayload.length, "bytes");
        console.log("  Encode gas:", encodeGas);
        console.log("  Decode gas:", decodeGas);
        console.log("  Total gas:", encodeGas + decodeGas);
        console.log("  Gas per byte:", (encodeGas + decodeGas) / odosPayload.length);
    }
    
    /**
     * @notice Simple test to focus on payload size and encoding/decoding
     */
    function test_SimpleDecodeGasMeasurement() public {
        console.log("==========================================");
        console.log("     SIMPLE DECODE GAS MEASUREMENT");
        console.log("==========================================");
        
        console.log("PAYLOAD SIZE:");
        console.log(vm.toString(odosPayload.length));
        
        // Warmup call to avoid first-call anomalies
        bytes memory warmup = swapper.decodeOdosPayload(encodedPath);
        require(warmup.length == odosPayload.length, "Warmup failed");
        
        // Actual gas measurement
        uint256 startGas = gasleft();
        bytes memory decoded = swapper.decodeOdosPayload(encodedPath);
        uint256 gasUsed = startGas - gasleft();
        
        console.log("DECODE GAS:");
        console.log(vm.toString(gasUsed));
        
        if (odosPayload.length > 0) {
            console.log("GAS PER BYTE:");
            console.log(vm.toString(gasUsed / odosPayload.length));
        }
        
        // Verify correctness
        bool hashes_match = keccak256(decoded) == keccak256(odosPayload);
        require(hashes_match, "Hashes don't match");
        
        console.log("==========================================");
    }
    
    /**
     * @notice Helper function to generate Odos API payload for WETH to USDC swap
     * @param inputAmount The amount of WETH to swap in wei (e.g., 10000000000000000 for 0.01 WETH)
     * @param slippagePct The slippage tolerance in percentage (e.g., 0.3 for 0.3%)
     * @return payload The Odos API payload for the swap
     */
    function getOdosPayloadForWethToUsdc(uint256 inputAmount, uint256 slippagePct) public returns (bytes memory) {
        // WETH and USDC addresses on mainnet
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        
        // Log what we're attempting to do
        console.log("Attempting to get Odos payload for WETH->USDC swap");
        console.log("Input amount:", inputAmount);
        
        // Use vm.ffi to make HTTP requests to Odos API
        string[] memory inputs = new string[](3);
        inputs[0] = "curl";
        inputs[1] = "-s";
        inputs[2] = string(abi.encodePacked(
            "https://api.odos.xyz/sor/quote/v2 -X POST -H 'Content-Type: application/json' -d '{",
            "\"chainId\": 1,",
            "\"inputTokens\": [{\"tokenAddress\": \"", vm.toString(weth), "\", \"amount\": \"", vm.toString(inputAmount), "\"}],",
            "\"outputTokens\": [{\"tokenAddress\": \"", vm.toString(usdc), "\", \"proportion\": 1}],",
            "\"userAddr\": \"", vm.toString(address(this)), "\",",
            "\"slippageLimitPercent\": ", vm.toString(slippagePct), ",",
            "\"disableRFQs\": true,",
            "\"compact\": true",
            "}'"
        ));
        
        bytes memory quoteResponse;
        
        quoteResponse = vm.ffi(inputs);
        
        // Log the response for debugging
        string memory quoteResponseStr = string(quoteResponse);
        if (bytes(quoteResponseStr).length > 100) {
            console.log("Quote response (truncated):", truncateString(quoteResponseStr, 100));
        } else {
            console.log("Quote response:", quoteResponseStr);
        }
        
        // Parse JSON response to extract pathId
        string memory pathId = extractPathId(quoteResponseStr);
        console.log("Extracted pathId:", pathId);
        
        // Get assembled transaction
        inputs[2] = string(abi.encodePacked(
            "https://api.odos.xyz/sor/assemble -X POST -H 'Content-Type: application/json' -d '{",
            "\"userAddr\": \"", vm.toString(address(this)), "\",",
            "\"pathId\": \"", pathId, "\",",
            "\"simulate\": false",
            "}'"
        ));
        
        bytes memory assembleResponse;
        assembleResponse = vm.ffi(inputs);
        
        // Log the response for debugging
        string memory assembleResponseStr = string(assembleResponse);
        if (bytes(assembleResponseStr).length > 100) {
            console.log("Assemble response (truncated):", truncateString(assembleResponseStr, 100));
        } else {
            console.log("Assemble response:", assembleResponseStr);
        }
        
        // Extract transaction data from response
        bytes memory payload = extractTransactionData(assembleResponseStr);
        console.log("Extracted payload length:", payload.length);
        
        return payload;
    }
    
    /**
     * @notice Helper function to check if a string contains a substring
     * @param haystack The string to search in
     * @param needle The substring to find
     * @return true if the substring is found, false otherwise
     */
    function containsString(string memory haystack, string memory needle) internal pure returns (bool) {
        bytes memory haystackBytes = bytes(haystack);
        bytes memory needleBytes = bytes(needle);
        
        if (needleBytes.length > haystackBytes.length) {
            return false;
        }
        
        for (uint i = 0; i <= haystackBytes.length - needleBytes.length; i++) {
            bool found = true;
            for (uint j = 0; j < needleBytes.length; j++) {
                if (haystackBytes[i + j] != needleBytes[j]) {
                    found = false;
                    break;
                }
            }
            if (found) {
                return true;
            }
        }
        
        return false;
    }
    
    /**
     * @notice Helper function to truncate a string to a specific length
     * @param str The string to truncate
     * @param maxLength The maximum length of the string
     * @return The truncated string
     */
    function truncateString(string memory str, uint maxLength) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        if (strBytes.length <= maxLength) {
            return str;
        }
        
        bytes memory result = new bytes(maxLength + 3); // +3 for "..."
        for (uint i = 0; i < maxLength; i++) {
            result[i] = strBytes[i];
        }
        result[maxLength] = '.';
        result[maxLength + 1] = '.';
        result[maxLength + 2] = '.';
        
        return string(result);
    }
    
    /**
     * @notice Helper function to extract pathId from Odos quote response
     * @param response The JSON response from the Odos API
     * @return pathId The extracted pathId
     */
    function extractPathId(string memory response) internal pure returns (string memory) {
        // Find the pathId in the response
        bytes memory responseBytes = bytes(response);
        bytes memory pathIdKey = bytes("\"pathId\":\"");
        
        uint startPos = indexOf(responseBytes, pathIdKey);
        if (startPos == type(uint).max) {
            return "";
        }
        
        startPos += pathIdKey.length;
        uint endPos = indexOf(responseBytes, bytes("\""), startPos);
        if (endPos == type(uint).max) {
            return "";
        }
        
        // Extract the pathId substring
        bytes memory pathId = new bytes(endPos - startPos);
        for (uint i = 0; i < pathId.length; i++) {
            pathId[i] = responseBytes[startPos + i];
        }
        
        return string(pathId);
    }
    
    /**
     * @notice Helper function to extract transaction data from Odos assemble response
     * @param response The JSON response from the Odos API
     * @return data The extracted transaction data
     */
    function extractTransactionData(string memory response) internal pure returns (bytes memory) {
        // Find the data field in the response
        bytes memory responseBytes = bytes(response);
        bytes memory dataKey = bytes("\"data\":\"");
        
        uint startPos = indexOf(responseBytes, dataKey);
        if (startPos == type(uint).max) {
            return "";
        }
        
        startPos += dataKey.length;
        uint endPos = indexOf(responseBytes, bytes("\""), startPos);
        if (endPos == type(uint).max) {
            return "";
        }
        
        // Extract the data substring
        bytes memory hexData = new bytes(endPos - startPos);
        for (uint i = 0; i < hexData.length; i++) {
            hexData[i] = responseBytes[startPos + i];
        }
        
        // Convert hex string to bytes
        return hexToBytes(string(hexData));
    }
    
    /**
     * @notice Helper function to find the index of a substring in a string
     * @param haystack The string to search in
     * @param needle The substring to find
     * @param startIndex The index to start searching from
     * @return The index of the first occurrence of the substring, or max uint if not found
     */
    function indexOf(bytes memory haystack, bytes memory needle, uint startIndex) internal pure returns (uint) {
        if (needle.length == 0) {
            return startIndex;
        }
        
        if (startIndex + needle.length > haystack.length) {
            return type(uint).max;
        }
        
        for (uint i = startIndex; i <= haystack.length - needle.length; i++) {
            bool found = true;
            for (uint j = 0; j < needle.length; j++) {
                if (haystack[i + j] != needle[j]) {
                    found = false;
                    break;
                }
            }
            if (found) {
                return i;
            }
        }
        
        return type(uint).max;
    }
    
    /**
     * @notice Helper function to find the index of a substring in a string
     * @param haystack The string to search in
     * @param needle The substring to find
     * @return The index of the first occurrence of the substring, or max uint if not found
     */
    function indexOf(bytes memory haystack, bytes memory needle) internal pure returns (uint) {
        return indexOf(haystack, needle, 0);
    }
    
    /**
     * @notice Helper function to convert a hex string to bytes
     * @param hexStr The hex string to convert (without 0x prefix)
     * @return The converted bytes
     */
    function hexToBytes(string memory hexStr) internal pure returns (bytes memory) {
        bytes memory bStr = bytes(hexStr);
        bytes memory result;
        
        // Check if it has 0x prefix
        uint start = 0;
        if (bStr.length >= 2 && bStr[0] == "0" && (bStr[1] == "x" || bStr[1] == "X")) {
            start = 2;
        }
        
        // Each byte requires 2 hex characters
        uint len = (bStr.length - start) / 2;
        result = new bytes(len);
        
        for (uint i = 0; i < len; i++) {
            uint8 high = uint8(hexCharToInt(bStr[start + i * 2]));
            uint8 low = uint8(hexCharToInt(bStr[start + i * 2 + 1]));
            result[i] = bytes1(high * 16 + low);
        }
        
        return result;
    }
    
    /**
     * @notice Helper function to convert a hex character to its integer value
     * @param c The hex character
     * @return The integer value of the hex character
     */
    function hexCharToInt(bytes1 c) internal pure returns (uint8) {
        if (c >= bytes1("0") && c <= bytes1("9")) {
            return uint8(c) - uint8(bytes1("0"));
        }
        if (c >= bytes1("a") && c <= bytes1("f")) {
            return 10 + uint8(c) - uint8(bytes1("a"));
        }
        if (c >= bytes1("A") && c <= bytes1("F")) {
            return 10 + uint8(c) - uint8(bytes1("A"));
        }
        revert("Invalid hex character");
    }
}