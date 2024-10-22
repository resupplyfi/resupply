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
    ICore public immutable core;

    constructor(address _core) {
        core = ICore(_core);
    }

    modifier onlyOwner() {
        require(msg.sender == address(core), "!core");
        _;
    }

    function owner() public view returns (address) {
        return address(core);
    }
}