// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "src/protocol/fraxlend/FraxlendPair.sol";
import "frax-std/FraxTest.sol";

contract ShowFraxlendPairCreationCode {
    function run() public view returns (bytes memory _creationCode) {
        _creationCode = type(FraxlendPair).creationCode;
        console.log("Creation Code of FraxlendPair: ");
        console.logBytes(_creationCode);
    }
}
