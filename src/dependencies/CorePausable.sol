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

    modifier whenProtocolNotPaused() {
        require(!isProtocolPaused(), "Paused");
        _;
    }

    modifier whenProtocolPaused() {
        require(isProtocolPaused(), "!Paused");
        _;
    }

    function isProtocolPaused() public view returns (bool) {
        return core.isProtocolPaused();
    }
}
