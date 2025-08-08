// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { stdJson } from "lib/forge-std/src/StdJson.sol";
import { console } from "lib/forge-std/src/console.sol";
import { Test } from "lib/forge-std/src/Test.sol";

library RetentionProgramJsonParser {
    using stdJson for string;

    struct RetentionData {
        address[] users;
        uint256[] amounts;
    }

    function parseRetentionSnapshot(string memory json) internal pure returns (RetentionData memory data) {
        string[] memory lines = splitString(json, '\n');
        
        // Count valid data lines first
        uint256 validLineCount = 0;
        for (uint256 i = 0; i < lines.length; i++) {
            if (isDataLine(lines[i])) {
                validLineCount++;
            }
        }
        
        // Initialize arrays with correct size
        data.users = new address[](validLineCount);
        data.amounts = new uint256[](validLineCount);
        
        uint256 dataIndex = 0;
        for (uint256 i = 0; i < lines.length; i++) {
            if (!isDataLine(lines[i])) continue;
            (string memory addr, uint256 value) = parseLine(lines[i]);
            data.users[dataIndex] = parseAddress(addr);
            data.amounts[dataIndex] = value;
            dataIndex++;
        }
    }

    function isDataLine(string memory line) internal pure returns (bool) {
        string memory trimmed = trimWhitespace(line);
        return bytes(trimmed).length > 0 && 
               contains(trimmed, "\"") && 
               contains(trimmed, ":") &&
               !contains(trimmed, "{") && 
               !contains(trimmed, "}");
    }

    function extractAllAddresses(string memory json) internal pure returns (string[] memory) {
        bytes memory jsonBytes = bytes(json);
        uint256 addressCount = countAddresses(jsonBytes);
        
        string[] memory addresses = new string[](addressCount);
        uint256 addressIndex = 0;
        uint256 startIndex = 0;
        bool inAddress = false;
        
        for (uint256 i = 0; i < jsonBytes.length; i++) {
            // Skip whitespace and newlines
            if (jsonBytes[i] == ' ' || jsonBytes[i] == '\n' || jsonBytes[i] == '\r' || jsonBytes[i] == '\t') {
                continue;
            }
            
            // Look for the start of an address (quote after opening brace, comma, or newline)
            if (jsonBytes[i] == '"' && !inAddress) {
                // Check if this is the start of an address (after {, ,, or whitespace)
                bool isStartOfKey = false;
                if (i > 0) {
                    // Look backwards to find the last non-whitespace character
                    for (uint256 j = i - 1; j >= 0; j--) {
                        if (jsonBytes[j] == ' ' || jsonBytes[j] == '\n' || jsonBytes[j] == '\r' || jsonBytes[j] == '\t') {
                            continue;
                        }
                        if (jsonBytes[j] == '{' || jsonBytes[j] == ',') {
                            isStartOfKey = true;
                        }
                        break;
                    }
                }
                
                if (isStartOfKey) {
                    startIndex = i + 1;
                    inAddress = true;
                }
            } else if (jsonBytes[i] == '"' && inAddress) {
                // Extract the address
                uint256 addressLength = i - startIndex;
                bytes memory addressBytes = new bytes(addressLength);
                for (uint256 j = 0; j < addressLength; j++) {
                    addressBytes[j] = jsonBytes[startIndex + j];
                }
                addresses[addressIndex] = string(addressBytes);
                addressIndex++;
                inAddress = false;
            }
        }
        
        return addresses;
    }

    function countAddresses(bytes memory jsonBytes) internal pure returns (uint256) {
        uint256 count = 0;
        
        for (uint256 i = 0; i < jsonBytes.length - 1; i++) {
            // Skip whitespace and newlines
            if (jsonBytes[i] == ' ' || jsonBytes[i] == '\n' || jsonBytes[i] == '\r' || jsonBytes[i] == '\t') {
                continue;
            }
            
            // Count quotes that come after {, ,, or whitespace
            if (jsonBytes[i] == '"' && i > 0) {
                // Look backwards to find the last non-whitespace character
                for (uint256 j = i - 1; j >= 0; j--) {
                    if (jsonBytes[j] == ' ' || jsonBytes[j] == '\n' || jsonBytes[j] == '\r' || jsonBytes[j] == '\t') {
                        continue;
                    }
                    if (jsonBytes[j] == '{' || jsonBytes[j] == ',') {
                        count++;
                    }
                    break;
                }
            }
        }
        
        return count;
    }

    function splitString(string memory str, bytes1 delimiter) internal pure returns (string[] memory) {
        bytes memory strBytes = bytes(str);
        uint256 count = 1;
        
        // Count delimiters
        for (uint256 i = 0; i < strBytes.length; i++) {
            if (strBytes[i] == delimiter) count++;
        }
        
        string[] memory result = new string[](count);
        uint256 index = 0;
        uint256 start = 0;
        
        // Split by delimiter
        for (uint256 i = 0; i < strBytes.length; i++) {
            if (strBytes[i] == delimiter) {
                result[index] = substring(str, start, i);
                index++;
                start = i + 1;
            }
        }
        result[index] = substring(str, start, strBytes.length);
        
        return result;
    }

    function substring(string memory str, uint256 startIndex, uint256 endIndex) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        bytes memory result = new bytes(endIndex - startIndex);
        
        for (uint256 i = startIndex; i < endIndex; i++) {
            result[i - startIndex] = strBytes[i];
        }
        
        return string(result);
    }

    function contains(string memory str, string memory searchStr) internal pure returns (bool) {
        bytes memory strBytes = bytes(str);
        bytes memory searchBytes = bytes(searchStr);
        
        for (uint256 i = 0; i <= strBytes.length - searchBytes.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < searchBytes.length; j++) {
                if (strBytes[i + j] != searchBytes[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return true;
        }
        return false;
    }

    function parseLine(string memory line) internal pure returns (string memory addr, uint256 value) {
        bytes memory lineBytes = bytes(line);
        
        // Find the first quote
        uint256 firstQuoteIndex = 0;
        for (uint256 i = 0; i < lineBytes.length; i++) {
            if (lineBytes[i] == '"') {
                firstQuoteIndex = i;
                break;
            }
        }
        
        // Find the second quote
        uint256 secondQuoteIndex = 0;
        for (uint256 i = firstQuoteIndex + 1; i < lineBytes.length; i++) {
            if (lineBytes[i] == '"') {
                secondQuoteIndex = i;
                break;
            }
        }
        
        if (firstQuoteIndex == 0 || secondQuoteIndex == 0) return ("", 0);
        
        // Extract address (between quotes)
        addr = substring(line, firstQuoteIndex + 1, secondQuoteIndex);
        
        // Find the colon after the second quote
        uint256 colonIndex = 0;
        for (uint256 i = secondQuoteIndex + 1; i < lineBytes.length; i++) {
            if (lineBytes[i] == ':') {
                colonIndex = i;
                break;
            }
        }
        
        if (colonIndex == 0) return ("", 0);
        
        // Extract value (remove comma if present and trim whitespace)
        string memory valueStr = substring(line, colonIndex + 1, lineBytes.length);
        valueStr = trimWhitespace(valueStr);
        
        // Remove trailing comma if present
        if (bytes(valueStr).length > 0 && bytes(valueStr)[bytes(valueStr).length - 1] == ',') {
            valueStr = substring(valueStr, 0, bytes(valueStr).length - 1);
        }
        
        value = parseInteger(valueStr);
    }

    function parseInteger(string memory valueStr) internal pure returns (uint256) {
        bytes memory valueBytes = bytes(valueStr);
        uint256 result = 0;
        
        for (uint256 i = 0; i < valueBytes.length; i++) {
            if (valueBytes[i] >= 0x30 && valueBytes[i] <= 0x39) { // ASCII for '0' to '9'
                result = result * 10 + (uint8(valueBytes[i]) - 0x30);
            }
        }
        
        return result;
    }

    function trimWhitespace(string memory str) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        uint256 start = 0;
        uint256 end = strBytes.length;
        
        // Find start (skip leading whitespace)
        while (start < end && (strBytes[start] == ' ' || strBytes[start] == '\t' || strBytes[start] == '\n' || strBytes[start] == '\r')) {
            start++;
        }
        
        // Find end (skip trailing whitespace)
        while (end > start && (strBytes[end - 1] == ' ' || strBytes[end - 1] == '\t' || strBytes[end - 1] == '\n' || strBytes[end - 1] == '\r')) {
            end--;
        }
        
        if (start >= end) return "";
        
        bytes memory result = new bytes(end - start);
        for (uint256 i = start; i < end; i++) {
            result[i - start] = strBytes[i];
        }
        
        return string(result);
    }

    function parseAddress(string memory addr) internal pure returns (address) {
        bytes memory addrBytes = bytes(addr);
        require(addrBytes.length == 42 && addrBytes[0] == '0' && addrBytes[1] == 'x', "Invalid address format");
        
        uint256 result = 0;
        for (uint256 i = 2; i < 42; i++) {
            uint256 digit;
            if (addrBytes[i] >= 0x30 && addrBytes[i] <= 0x39) { // 0-9
                digit = uint8(addrBytes[i]) - 0x30;
            } else if (addrBytes[i] >= 0x61 && addrBytes[i] <= 0x66) { // a-f
                digit = uint8(addrBytes[i]) - 0x61 + 10;
            } else if (addrBytes[i] >= 0x41 && addrBytes[i] <= 0x46) { // A-F
                digit = uint8(addrBytes[i]) - 0x41 + 10;
            } else {
                revert("Invalid hex character");
            }
            result = result * 16 + digit;
        }
        
        return address(uint160(result));
    }
}

contract RetentionProgramJsonParserTest is Test {
    using RetentionProgramJsonParser for *;

    function testParseRetentionSnapshot() public {
        string memory json = vm.readFile("deployment/data/ip_retention_snapshot.json");
        
        // Test parsing a single line first
        string memory testLine = '  "0x00c04AE980A41825FCb505797d394090295B5813": 4151831390215934037907417,';
        console.log("Testing line:", testLine);
        
        (string memory addr, uint256 value) = RetentionProgramJsonParser.parseLine(testLine);
        console.log("Parsed address:", addr);
        console.log("Parsed value:", value);
        
        // Now test the full parsing
        RetentionProgramJsonParser.RetentionData memory data = RetentionProgramJsonParser.parseRetentionSnapshot(json);
        console.log("Total users parsed:", data.users.length);
        
        if (data.users.length > 0) {
            console.log("First user:", data.users[0]);
            console.log("First amount:", data.amounts[0]);
        }
    }
}