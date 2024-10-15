// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;
import "../interfaces/ICore.sol";

/**
    @title Core Ownable
    @author Prisma Finance (with edits by Relend.fi)
    @notice Contracts inheriting `CoreOwnable` have the same owner as `Core`.
            The ownership cannot be independently modified or renounced.
 */
contract CoreOwnable {
    ICore public immutable RELEND_CORE;

    constructor(address _core) {
        RELEND_CORE = ICore(_core);
    }

    modifier onlyOwner() {
        require(msg.sender == RELEND_CORE.owner(), "Only owner");
        _;
    }

    function owner() public view returns (address) {
        return RELEND_CORE.owner();
    }

    function guardian() public view returns (address) {
        return RELEND_CORE.guardian();
    }
}