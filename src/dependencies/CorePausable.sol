// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;
import {ICore} from "../interfaces/ICore.sol";
import {CoreOwnable} from "./CoreOwnable.sol";

/**
    @title  Core Pausable
    @author Relend.fi
    @notice Contracts inheriting `CorePausable` can access the core contract's paused state.
 */
contract CorePausable is CoreOwnable {
    constructor(address _core) CoreOwnable(_core) {
    }

    modifier whenNotPaused() {
        require(!CORE.paused(), "Paused");
        _;
    }

    modifier whenPaused() {
        require(CORE.paused(), "!Paused");
        _;
    }

    function paused() public view virtual returns (bool) {
        return CORE.paused();
    }
}