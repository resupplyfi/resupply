// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { CoreOwnable } from "../../src/dependencies/CoreOwnable.sol";

contract MockPair is CoreOwnable {
    uint256 public value;

    constructor(address _core) CoreOwnable(_core) {}

    function setValue(uint256 _value) external onlyOwner {
        value = _value;
    }
}