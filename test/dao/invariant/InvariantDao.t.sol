// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.22 <0.9.0;

import { Setup } from "../../Setup.sol";

/// @notice Common logic needed by all invariant tests.
abstract contract Invariant_DaoTest is Setup {

    function setUp() public virtual override {
        super.setUp();

        // Prevent these contracts from being fuzzed as `msg.sender`.
        // excludeSender();
        // ...
    }
}
