// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;
import {ICore} from "../interfaces/ICore.sol";

/**
    @title Core Ownable
    @author Prisma Finance (with edits by Relend.fi)
    @notice Contracts inheriting `CoreOwnable` have the same owner as `Core`.
            The ownership cannot be independently modified or renounced.
 */
contract CoreOwnable {
    ICore public immutable CORE;

    constructor(address _core) {
        CORE = ICore(_core);
    }

    modifier onlyOwner() {
        require(msg.sender == CORE.owner(), "Only owner");
        _;
    }

    function owner() public view returns (address) {
        return CORE.owner();
    }

    function guardian() public view returns (address) {
        return CORE.guardian();
    }
}