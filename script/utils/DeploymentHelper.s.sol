// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "lib/forge-std/src/Script.sol";
import {stdJson} from "lib/forge-std/src/StdJson.sol";

abstract contract DeploymentHelper is Script {
    using stdJson for string;

    function writeAddressesToFile(
        string memory fileName,
        mapping(string => address) storage deployedAddresses
    ) internal {
        string memory json = "";
        
        // Create a temporary array to store the key-value pairs
        string[] memory keys = new string[](100); // Adjust size as needed
        address[] memory values = new address[](100);
        uint256 count = 0;
        
        keys[count] = "GOV_STAKER";
        values[count] = deployedAddresses["GOV_STAKER"];
        count++;
        
        // Convert to JSON string
        json = _generateJson(keys, values, count);
        
        // Write to file
        vm.writeJson(json, fileName);
    }
    
    function _generateJson(
        string[] memory keys,
        address[] memory values,
        uint256 count
    ) internal pure returns (string memory) {
        string memory json = "{";
        
        for (uint256 i = 0; i < count; i++) {
            if (i > 0) {
                json = string.concat(json, ",");
            }
            json = string.concat(
                json,
                '"',
                keys[i],
                '": "',
                vm.toString(values[i]),
                '"'
            );
        }
        
        json = string.concat(json, "}");
        return json;
    }
}