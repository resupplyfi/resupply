// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { console } from "lib/forge-std/src/console.sol";
import { Vm } from "lib/forge-std/src/Vm.sol";

/**
 * @title LI.FI
 * @notice Utility library for interacting with the LI.FI API in Forge tests
 */
library LifiApi {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    address public constant LIFI_ROUTER = 0x1231DEB6f5749EF6cE6943a275A1D3E7486F4EaE;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    struct Quote {
        bytes payload;
        uint256 amountOutMin;
    }

    /**
     * @notice Get a swap payload from the LI.FI quote endpoint
     * @param inputToken The address of the input token
     * @param outputToken The address of the output token
     * @param inputAmount The amount of input token (in wei)
     * @param slippagePct The slippage tolerance in percentage (e.g. 3 for 3%)
     * @param fromAddress The address that will call the LI.FI router
     * @param toAddress The address that should receive output tokens
     * @return quote The encoded swap payload and quoted minimum output
     */
    function getQuote(address inputToken, address outputToken, uint256 inputAmount, uint256 slippagePct, address fromAddress, address toAddress) public returns (Quote memory quote) {
        console.log("Attempting to get LI.FI payload for swap");
        console.log("Input amount:", inputAmount);

        string memory url = string(abi.encodePacked("https://li.quest/v1/quote?", "fromChain=1", "&toChain=1", "&fromToken=", vm.toString(inputToken), "&toToken=", vm.toString(outputToken), "&fromAmount=", vm.toString(inputAmount), "&fromAddress=", vm.toString(fromAddress), "&toAddress=", vm.toString(toAddress), "&slippage=", slippageString(slippagePct), "&skipSimulation=true", "&integrator=resupply"));

        string[] memory inputs = new string[](3);
        inputs[0] = "curl";
        inputs[1] = "-s";
        inputs[2] = url;

        console.log("Curl command (quote):");
        console.log(url);

        bytes memory quoteResponse = vm.ffi(inputs);
        console.log("Quote response raw length:", quoteResponse.length);

        quote.payload = extractTransactionData(string(quoteResponse));
        quote.amountOutMin = extractAmountOutMin(string(quoteResponse));

        address transactionTarget = extractTransactionTo(string(quoteResponse));
        address approvalAddress = extractApprovalAddress(string(quoteResponse));
        require(transactionTarget == LIFI_ROUTER, "!lifi_target");
        require(approvalAddress == LIFI_ROUTER, "!lifi_approval");

        console.log("Extracted payload length:", quote.payload.length);
        console.log("Extracted amountOutMin:", quote.amountOutMin);
    }

    function getPayload(address inputToken, address outputToken, uint256 inputAmount, uint256 slippagePct, address fromAddress, address toAddress) public returns (bytes memory payload) {
        payload = getQuote(inputToken, outputToken, inputAmount, slippagePct, fromAddress, toAddress).payload;
    }

    /**
     * @notice Extract the transaction data from a quote response
     * @param response The JSON response from the LI.FI API
     * @return data The extracted transaction data
     */
    function extractTransactionData(string memory response) internal pure returns (bytes memory) {
        return hexToBytes(extractStringValue(response, "\"transactionRequest\"", "data"));
    }

    function extractTransactionTo(string memory response) internal pure returns (address) {
        return stringToAddress(extractStringValue(response, "\"transactionRequest\"", "to"));
    }

    function extractApprovalAddress(string memory response) internal pure returns (address) {
        return stringToAddress(extractStringValue(response, "\"estimate\"", "approvalAddress"));
    }

    function extractStringValue(string memory response, string memory section, string memory field) internal pure returns (string memory) {
        bytes memory responseBytes = bytes(response);
        uint256 startPos = indexOf(responseBytes, bytes(section));
        if (startPos == type(uint256).max) return "";

        bytes memory fieldKey = bytes(string(abi.encodePacked("\"", field, "\"")));
        startPos = indexOf(responseBytes, fieldKey, startPos);
        if (startPos == type(uint256).max) return "";

        startPos = indexOf(responseBytes, bytes(":"), startPos);
        if (startPos == type(uint256).max) return "";

        startPos++;
        while (startPos < responseBytes.length && isWhitespace(responseBytes[startPos])) {
            startPos++;
        }
        if (startPos >= responseBytes.length || responseBytes[startPos] != "\"") return "";

        startPos++;
        uint256 endPos = indexOf(responseBytes, bytes("\""), startPos);
        if (endPos == type(uint256).max) return "";

        bytes memory valueBytes = new bytes(endPos - startPos);
        for (uint256 i = 0; i < valueBytes.length; i++) {
            valueBytes[i] = responseBytes[startPos + i];
        }

        return string(valueBytes);
    }

    function extractAmountOutMin(string memory response) internal pure returns (uint256) {
        bytes memory amountBytes = bytes(extractStringValue(response, "\"estimate\"", "toAmountMin"));
        uint256 amount;
        for (uint256 i = 0; i < amountBytes.length; i++) {
            bytes1 char = amountBytes[i];
            if (char < "0" || char > "9") revert("Invalid amount");
            amount = amount * 10 + uint8(char) - uint8(bytes1("0"));
        }
        return amount;
    }

    function isWhitespace(bytes1 char) internal pure returns (bool) {
        return char == " " || char == "\n" || char == "\r" || char == "\t";
    }

    /**
     * @notice Find the index of a substring in a string
     * @param haystack The string to search in
     * @param needle The substring to find
     * @return The index of the first occurrence of the substring, or max uint if not found
     */
    function indexOf(bytes memory haystack, bytes memory needle) internal pure returns (uint256) {
        return indexOf(haystack, needle, 0);
    }

    /**
     * @notice Find the index of a substring in a string, starting from a specific index
     * @param haystack The string to search in
     * @param needle The substring to find
     * @param startIndex The index to start searching from
     * @return The index of the first occurrence of the substring, or max uint if not found
     */
    function indexOf(bytes memory haystack, bytes memory needle, uint256 startIndex) internal pure returns (uint256) {
        if (needle.length == 0) {
            return startIndex;
        }

        if (startIndex + needle.length > haystack.length) {
            return type(uint256).max;
        }

        for (uint256 i = startIndex; i <= haystack.length - needle.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < needle.length; j++) {
                if (haystack[i + j] != needle[j]) {
                    found = false;
                    break;
                }
            }
            if (found) {
                return i;
            }
        }

        return type(uint256).max;
    }

    /**
     * @notice Convert a hex string to bytes
     * @param hexStr The hex string to convert
     * @return The converted bytes
     */
    function hexToBytes(string memory hexStr) internal pure returns (bytes memory) {
        bytes memory bStr = bytes(hexStr);
        bytes memory result;

        uint256 start = 0;
        if (bStr.length >= 2 && bStr[0] == "0" && (bStr[1] == "x" || bStr[1] == "X")) {
            start = 2;
        }

        uint256 len = (bStr.length - start) / 2;
        result = new bytes(len);

        for (uint256 i = 0; i < len; i++) {
            uint8 high = uint8(hexCharToInt(bStr[start + i * 2]));
            uint8 low = uint8(hexCharToInt(bStr[start + i * 2 + 1]));
            result[i] = bytes1(high * 16 + low);
        }

        return result;
    }

    function stringToAddress(string memory addressString) internal pure returns (address) {
        bytes memory bStr = bytes(addressString);
        uint256 start = 0;
        if (bStr.length >= 2 && bStr[0] == "0" && (bStr[1] == "x" || bStr[1] == "X")) {
            start = 2;
        }
        require(bStr.length == start + 40, "Invalid address");

        uint160 parsed;
        for (uint256 i = 0; i < 40; i++) {
            parsed = parsed * 16 + uint160(hexCharToInt(bStr[start + i]));
        }

        return address(parsed);
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

    function slippageString(uint256 slippagePct) internal view returns (string memory) {
        require(slippagePct <= 100, "Invalid slippage");
        if (slippagePct == 100) return "1";
        if (slippagePct < 10) {
            return string(abi.encodePacked("0.0", vm.toString(slippagePct)));
        }
        return string(abi.encodePacked("0.", vm.toString(slippagePct)));
    }
}
