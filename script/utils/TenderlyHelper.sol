    //SPDX-License-Identifier: MIT
    pragma solidity ^0.8.22;

    import {console} from "lib/forge-std/src/console.sol";
    import {SafeHelper} from "script/utils/SafeHelper.sol";

    // All helper functions take care of setting the values in both local environment + fork environment.
    contract TenderlyHelper is SafeHelper {

        string public URL = vm.envString("TENDERLY_URL");

        function skipTime(uint256 _seconds) public {
            vm.warp(_seconds);
            sendCurlRequest("evm_increaseTime", vm.toString(_seconds));
        }

        function skipBlocks(uint256 _blocks) public {
            uint256 currentBlock = block.number;
            vm.roll(currentBlock + _blocks); // Adjust the parameter to skip forward the specified number of blocks
            for (uint256 i = 0; i < _blocks; i++) {
                sendCurlRequest("evm_mine");
            }
        }

        function setTokenBalance(address token, address user, uint256 amount) public {
            deal(token, user, amount);
            sendCurlRequest("tenderly_setErc20Balance", vm.toString(token), vm.toString(user), toHexString(amount));
        }

        function setEthBalance(address user, uint256 amount) public {
            deal(user, amount);
            sendCurlRequest("tenderly_setBalance", vm.toString(user), toHexString(amount));
        }

        function getEthBalance(address user, uint256 blockNumber) public returns (uint256) {
            string memory result = sendCurlRequest("eth_getBalance", vm.toString(user), vm.toString(blockNumber));
            return extractValueFromResult(result, '"result":"');
        }

        function syncBlockNumber() public returns (uint256) {
            string memory result = sendCurlRequest("eth_blockNumber");
            uint256 blockNumber = extractValueFromResult(result, '"result":"');
            vm.roll(blockNumber);
            return blockNumber;
        }

        function syncTimestamp() public returns (uint256) {
            string memory result = sendCurlRequest("eth_getBlockByNumber", "latest", false);
            uint256 timestamp = extractValueFromResult(result, '"timestamp":"');
            vm.warp(timestamp);
            return timestamp;
        }

        function sendCurlRequest(string memory method, string memory param1, bool param2) internal returns (string memory) {
            string memory param2Str = param2 ? "true" : "false";
            string memory data = string(abi.encodePacked('{"jsonrpc":"2.0","method":"', method, '","params":["', param1, '",', param2Str, '],"id":1}'));
            return sendRequest(data);
        }

        function sendCurlRequest(string memory method, string memory param1, string memory param2, string memory param3) internal returns (string memory) {
            string memory data = string(abi.encodePacked('{"jsonrpc":"2.0","method":"', method, '","params":["', param1, '","', param2, '","', param3, '"],"id":1}'));
            return sendRequest(data);
        }

        function sendCurlRequest(string memory method, string memory param1, string memory param2) internal returns (string memory) {
            string memory data = string(abi.encodePacked('{"jsonrpc":"2.0","method":"', method, '","params":["', param1, '","', param2, '"],"id":1}'));
            return sendRequest(data);
        }

        function sendCurlRequest(string memory method, string memory param1) internal returns (string memory) {
            string memory data = string(abi.encodePacked('{"jsonrpc":"2.0","method":"', method, '","params":["', param1, '"],"id":1}'));
            return sendRequest(data);
        }

        function sendCurlRequest(string memory method) internal returns (string memory) {
            string memory data = string(abi.encodePacked('{"jsonrpc":"2.0","method":"', method, '","params":[],"id":1}'));
            return sendRequest(data);
        }

        function sendRequest(string memory data) internal returns (string memory) {
            string[] memory curlCommand = new string[](9);
            curlCommand[0] = "curl";
            curlCommand[1] = "-X";
            curlCommand[2] = "POST";
            curlCommand[3] = "-H";
            curlCommand[4] = "Content-Type: application/json";
            curlCommand[5] = "-d";
            curlCommand[6] = data;
            curlCommand[7] = "-s";
            curlCommand[8] = URL;

            console.log("Sending request:", data);
            string memory result = string(vm.ffi(curlCommand));
            console.log("Response:", result);
            require(bytes(result).length > 0, "Empty response from RPC call");
            return result;
        }

        function extractValueFromResult(string memory result, string memory key) internal pure returns (uint256) {
            bytes memory resultBytes = bytes(result);
            bytes memory keyBytes = bytes(key);
            uint256 startIndex = findKeyIndex(resultBytes, keyBytes);
            uint256 endIndex = startIndex;
            while (endIndex < resultBytes.length && resultBytes[endIndex] != '"') {
                endIndex++;
            }
            bytes memory valueBytes = new bytes(endIndex - startIndex);
            for (uint256 i = startIndex; i < endIndex; i++) {
                valueBytes[i - startIndex] = resultBytes[i];
            }
            return hexStringToUint(string(valueBytes));
        }

        function findKeyIndex(bytes memory resultBytes, bytes memory keyBytes) internal pure returns (uint256) {
            for (uint256 i = 0; i < resultBytes.length - keyBytes.length; i++) {
                bool isMatch = true;
                for (uint256 j = 0; j < keyBytes.length; j++) {
                    if (resultBytes[i + j] != keyBytes[j]) {
                        isMatch = false;
                        break;
                    }
                }
                if (isMatch) {
                    return i + keyBytes.length;
                }
            }
            revert("Key not found");
        }

        function toHexString(uint256 value) internal pure returns (string memory) {
            if (value == 0) {
                return "0x0";
            }
            uint256 temp = value;
            uint256 length = 0;
            while (temp != 0) {
                length++;
                temp >>= 4;
            }
            bytes memory buffer = new bytes(2 + length);
            buffer[0] = "0";
            buffer[1] = "x";
            for (uint256 i = 2 + length - 1; i > 1; --i) {
                uint8 digit = uint8(value & 0xf);
                buffer[i] = digit < 10 ? bytes1(digit + 48) : bytes1(digit + 87);
                value >>= 4;
            }
            return string(buffer);
        }

        function hexStringToUint(string memory hexString) internal pure returns (uint256) {
            bytes memory hexBytes = bytes(hexString);
            uint256 value = 0;
            for (uint256 i = 0; i < hexBytes.length; i++) {
                uint256 byteValue = uint8(hexBytes[i]);
                if (byteValue >= 48 && byteValue <= 57) {
                    value = value * 16 + (byteValue - 48);
                } else if (byteValue >= 97 && byteValue <= 102) {
                    value = value * 16 + (byteValue - 87);
                } else if (byteValue >= 65 && byteValue <= 70) {
                    value = value * 16 + (byteValue - 55);
                }
            }
            return value;
        }
    }