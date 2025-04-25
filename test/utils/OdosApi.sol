// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { console } from "lib/forge-std/src/console.sol";
import { Vm } from "lib/forge-std/src/Vm.sol";

/**
 * @title Odos
 * @notice Utility library for interacting with the Odos API in Forge tests
 */
library OdosApi {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    
    /**
     * @notice Get a swap payload for WETH to USDC on Odos
     * @param inputAmount The amount of WETH to swap (in wei)
     * @param slippagePct The slippage tolerance in percentage (e.g., 0.3 for 0.3%)
     * @param userAddress The address of the user making the swap
     * @return payload The encoded swap payload
     */
    function getPayloadForWethToUsdc(
        uint256 inputAmount,
        uint256 slippagePct,
        address userAddress
    ) public returns (bytes memory) {
        console.log("Attempting to get Odos payload for WETH->USDC swap");
        console.log("Input amount:", inputAmount);
        
        // Get a quote from the Odos API
        string memory pathId = getQuote(
            WETH,
            USDC,
            inputAmount,
            slippagePct,
            userAddress
        );
        
        // Assemble the transaction
        bytes memory payload = assembleTransaction(pathId, userAddress);
        
        return payload;
    }

    function getPayload(
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 slippagePct,
        address userAddress
    ) public returns (bytes memory) {
        console.log("Attempting to get Odos payload for swap");
        console.log("Input amount:", inputAmount);
        
        // Get a quote from the Odos API
        string memory pathId = getQuote(
            inputToken,
            outputToken,
            inputAmount,
            slippagePct,
            userAddress
        );
        
        // Assemble the transaction
        bytes memory payload = assembleTransaction(pathId, userAddress);
        
        return payload;
    }
    
    /**
     * @notice Get a quote from the Odos API
     * @param inputToken The address of the input token
     * @param outputToken The address of the output token
     * @param inputAmount The amount of input token (in wei)
     * @param slippagePct The slippage tolerance in percentage
     * @param userAddress The address of the user making the swap
     * @return pathId The path ID returned by the Odos API
     */
    function getQuote(
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 slippagePct,
        address userAddress
    ) public returns (string memory) {
        string memory jsonData = string(abi.encodePacked(
            "{",
            "\"chainId\": 1,",
            "\"inputTokens\": [{\"tokenAddress\": \"", vm.toString(inputToken), "\", \"amount\": \"", vm.toString(inputAmount), "\"}],",
            "\"outputTokens\": [{\"tokenAddress\": \"", vm.toString(outputToken), "\", \"proportion\": 1}],",
            "\"userAddr\": \"", vm.toString(userAddress), "\",",
            "\"slippageLimitPercent\": ", vm.toString(slippagePct), ",",
            "\"disableRFQs\": true,",
            "\"compact\": true",
            "}"
        ));
        
        string[] memory inputs = new string[](9);
        inputs[0] = "curl";
        inputs[1] = "-s";
        inputs[2] = "-X";
        inputs[3] = "POST";
        inputs[4] = "-H";
        inputs[5] = "Content-Type: application/json";
        inputs[6] = "-d";
        inputs[7] = jsonData;
        inputs[8] = "https://api.odos.xyz/sor/quote/v2";
        
        console.log("Curl command (quote):");
        console.log(string(abi.encodePacked("curl -s -X POST ", inputs[8], " with data: ", jsonData)));
        
        bytes memory quoteResponse = vm.ffi(inputs);
        console.log("Quote response raw length:", quoteResponse.length);
        
        // Extract the path ID from the response
        string memory pathId = extractPathId(string(quoteResponse));
        console.log("Extracted pathId:", pathId);
        
        return pathId;
    }
    
    /**
     * @notice Assemble a transaction from a path ID
     * @param pathId The path ID returned by the Odos API
     * @param userAddress The address of the user making the swap
     * @return payload The encoded swap payload
     */
    function assembleTransaction(
        string memory pathId,
        address userAddress
    ) public returns (bytes memory) {
        string memory assembleJsonData = string(abi.encodePacked(
            "{",
            "\"userAddr\": \"", vm.toString(userAddress), "\",",
            "\"pathId\": \"", pathId, "\",",
            "\"simulate\": false",
            "}"
        ));
        
        string[] memory inputs = new string[](9);
        inputs[0] = "curl";
        inputs[1] = "-s";
        inputs[2] = "-X";
        inputs[3] = "POST";
        inputs[4] = "-H";
        inputs[5] = "Content-Type: application/json";
        inputs[6] = "-d";
        inputs[7] = assembleJsonData;
        inputs[8] = "https://api.odos.xyz/sor/assemble";
        
        console.log("Curl command (assemble):");
        console.log(string(abi.encodePacked("curl -s -X POST ", inputs[8], " with data: ", assembleJsonData)));
        
        bytes memory assembleResponse = vm.ffi(inputs);
        
        // Extract the transaction data from the response
        bytes memory payload = extractTransactionData(string(assembleResponse));
        console.log("Extracted payload length:", payload.length);
        
        return payload;
    }
    
    /**
     * @notice Extract the path ID from a quote response
     * @param response The JSON response from the Odos API
     * @return pathId The extracted path ID
     */
    function extractPathId(string memory response) internal pure returns (string memory) {
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
     * @notice Extract the transaction data from an assemble response
     * @param response The JSON response from the Odos API
     * @return data The extracted transaction data
     */
    function extractTransactionData(string memory response) internal pure returns (bytes memory) {
        bytes memory responseBytes = bytes(response);
        bytes memory transactionKey = bytes("\"transaction\":");
        bytes memory dataKey = bytes("\"data\":\"");
        
        uint startPos = indexOf(responseBytes, transactionKey);
        if (startPos == type(uint).max) {
            return "";
        }
        
        startPos = indexOf(responseBytes, dataKey, startPos);
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
     * @notice Find the index of a substring in a string
     * @param haystack The string to search in
     * @param needle The substring to find
     * @return The index of the first occurrence of the substring, or max uint if not found
     */
    function indexOf(bytes memory haystack, bytes memory needle) internal pure returns (uint) {
        return indexOf(haystack, needle, 0);
    }
    
    /**
     * @notice Find the index of a substring in a string, starting from a specific index
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
     * @notice Convert a hex string to bytes
     * @param hexStr The hex string to convert
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
     * @notice Convert a hex character to its integer value
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
