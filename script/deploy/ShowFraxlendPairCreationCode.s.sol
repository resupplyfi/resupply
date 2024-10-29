// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "src/protocol/ResupplyPair.sol";
import "frax-std/FraxTest.sol";

contract ShowFraxlendPairCreationCode {
    function run() public view returns (bytes memory _creationCode) {
        _creationCode = type(ResupplyPair).creationCode;
        console.log("Creation Code of ResupplyPair: ");
        console.logBytes(_creationCode);
    }
}
