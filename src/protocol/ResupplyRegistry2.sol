// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract Registry {

    mapping(string => address) private keyToAddress;

    string[] private keys;

    mapping(string => bool) public keyExists; // to prevent duplicates

    event EntryUpdated(string indexed key, address indexed addr);

    function setAddress(string memory key, address addr) public {
        require(bytes(key).length > 0, "Key cannot be empty");
        require(addr != address(0), "Address cannot be zero");

        // Add the key to the list if it's a new entry
        if (!keyExists[key]) {
            keys.push(key);
            keyExists[key] = true;
        }

        keyToAddress[key] = addr;

        emit EntryUpdated(key, addr);
    }

    function getAddress(string memory key) public view returns (address) {
        return keyToAddress[key];
    }

    function getAllKeys() public view returns (string[] memory) {
        return keys;
    }

    function getAllAddresses() public view returns (address[] memory) {
        address[] memory addresses = new address[](keys.length);
        for (uint i = 0; i < keys.length; i++) {
            addresses[i] = keyToAddress[keys[i]];
        }
        return addresses;
    }
}