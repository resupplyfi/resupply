// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { console } from "lib/forge-std/src/console.sol";
import { Vm } from "lib/forge-std/src/Vm.sol";

library EnsoApi {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    address public constant ENSO_ROUTER = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    struct Quote {
        bytes payload;
        uint256 amountOutMin;
    }

    function getQuote(address inputToken, address outputToken, uint256 inputAmount, uint256 slippageBps, address fromAddress, address receiver) public returns (Quote memory quote) {
        console.log("Attempting to get ENSO payload for swap");
        console.log("Input amount:", inputAmount);

        string memory url = string(abi.encodePacked(
            "https://api.enso.build/api/v1/shortcuts/route?",
            "chainId=1",
            "&fromAddress=", vm.toString(fromAddress),
            "&receiver=", vm.toString(receiver),
            "&routingStrategy=router",
            "&tokenIn=", vm.toString(inputToken),
            "&tokenOut=", vm.toString(outputToken),
            "&amountIn=", vm.toString(inputAmount),
            "&slippage=", vm.toString(slippageBps)
        ));

        string[] memory inputs = new string[](3);
        inputs[0] = "bash";
        inputs[1] = "-lc";
        inputs[2] = string(abi.encodePacked(
            "for i in 1 2 3 4 5 6 7 8 9 10; do out=$(curl -s '",
            url,
            "'); case $out in *'request limit'*) sleep 2 ;; *) printf '%s' \"$out\"; exit 0 ;; esac; done; printf '%s' \"$out\""
        ));

        console.log("Curl command (route):");
        console.log(url);

        bytes memory response = vm.ffi(inputs);
        string memory responseString = string(response);
        console.log("Route response raw length:", response.length);
        if (indexOf(bytes(responseString), bytes("request limit")) != type(uint256).max) {
            vm.skip(true);
        }

        quote.payload = extractTransactionData(responseString);
        quote.amountOutMin = extractAmountOutMin(responseString);

        address transactionTarget = extractTransactionTo(responseString);
        uint256 transactionValue = extractTransactionValue(responseString);
        require(transactionTarget == ENSO_ROUTER, "!enso_target");
        require(transactionValue == 0, "!enso_value");

        console.log("Extracted payload length:", quote.payload.length);
        console.log("Extracted amountOutMin:", quote.amountOutMin);
    }

    function getPayload(address inputToken, address outputToken, uint256 inputAmount, uint256 slippageBps, address fromAddress, address receiver) public returns (bytes memory payload) {
        payload = getQuote(inputToken, outputToken, inputAmount, slippageBps, fromAddress, receiver).payload;
    }

    function extractTransactionData(string memory response) internal pure returns (bytes memory) {
        return hexToBytes(extractStringValue(response, "\"tx\"", "data"));
    }

    function extractTransactionTo(string memory response) internal pure returns (address) {
        return stringToAddress(extractStringValue(response, "\"tx\"", "to"));
    }

    function extractTransactionValue(string memory response) internal pure returns (uint256) {
        return parseUint(extractStringValue(response, "\"tx\"", "value"));
    }

    function extractAmountOutMin(string memory response) internal pure returns (uint256) {
        return parseUint(extractStringValue(response, "", "minAmountOut"));
    }

    function extractStringValue(string memory response, string memory section, string memory field) internal pure returns (string memory) {
        bytes memory responseBytes = bytes(response);
        uint256 startPos;
        if (bytes(section).length > 0) {
            startPos = indexOf(responseBytes, bytes(section));
            if (startPos == type(uint256).max) return "";
        }

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

    function parseUint(string memory value) internal pure returns (uint256 amount) {
        bytes memory amountBytes = bytes(value);
        for (uint256 i = 0; i < amountBytes.length; i++) {
            bytes1 char = amountBytes[i];
            if (char < "0" || char > "9") revert("Invalid amount");
            amount = amount * 10 + uint8(char) - uint8(bytes1("0"));
        }
    }

    function isWhitespace(bytes1 char) internal pure returns (bool) {
        return char == " " || char == "\n" || char == "\r" || char == "\t";
    }

    function indexOf(bytes memory haystack, bytes memory needle) internal pure returns (uint256) {
        return indexOf(haystack, needle, 0);
    }

    function indexOf(bytes memory haystack, bytes memory needle, uint256 startIndex) internal pure returns (uint256) {
        if (needle.length == 0) return startIndex;
        if (startIndex + needle.length > haystack.length) return type(uint256).max;
        for (uint256 i = startIndex; i <= haystack.length - needle.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < needle.length; j++) {
                if (haystack[i + j] != needle[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return i;
        }
        return type(uint256).max;
    }

    function hexToBytes(string memory hexStr) internal pure returns (bytes memory) {
        bytes memory bStr = bytes(hexStr);
        uint256 start;
        if (bStr.length >= 2 && bStr[0] == "0" && (bStr[1] == "x" || bStr[1] == "X")) start = 2;
        uint256 len = (bStr.length - start) / 2;
        bytes memory result = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            uint8 high = uint8(hexCharToInt(bStr[start + i * 2]));
            uint8 low = uint8(hexCharToInt(bStr[start + i * 2 + 1]));
            result[i] = bytes1(high * 16 + low);
        }
        return result;
    }

    function stringToAddress(string memory addressString) internal pure returns (address) {
        bytes memory bStr = bytes(addressString);
        uint256 start;
        if (bStr.length >= 2 && bStr[0] == "0" && (bStr[1] == "x" || bStr[1] == "X")) start = 2;
        require(bStr.length == start + 40, "Invalid address");
        uint160 parsed;
        for (uint256 i = 0; i < 40; i++) {
            parsed = parsed * 16 + uint160(hexCharToInt(bStr[start + i]));
        }
        return address(parsed);
    }

    function hexCharToInt(bytes1 c) internal pure returns (uint8) {
        if (c >= bytes1("0") && c <= bytes1("9")) return uint8(c) - uint8(bytes1("0"));
        if (c >= bytes1("a") && c <= bytes1("f")) return 10 + uint8(c) - uint8(bytes1("a"));
        if (c >= bytes1("A") && c <= bytes1("F")) return 10 + uint8(c) - uint8(bytes1("A"));
        revert("Invalid hex character");
    }
}
