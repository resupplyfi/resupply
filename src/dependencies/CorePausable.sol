// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;
import {ICore} from "../interfaces/ICore.sol";
import {CoreOwnable} from "./CoreOwnable.sol";

/**
    @title  Core Pausable
    @author Relend.fi
    @notice Contracts inheriting `CorePausable` automatically get `CoreOwnable` 
            and can access the core contract's paused state.
 */
contract CorePausable is CoreOwnable {
    constructor(address _core) CoreOwnable(_core) {}

    modifier whenNotPaused() {
        require(!isPaused(), "Paused");
        _;
    }

    modifier whenPaused() {
        require(isPaused(), "!Paused");
        _;
    }

    function isPaused() public view returns (bool) {
        return CORE.isPaused(address(this));
    }
}
