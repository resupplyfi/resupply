// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { GovToken } from "src/dao/GovToken.sol";

contract GovTokenHarness is GovToken {
    constructor(
        address _core,
        address _vesting,
        uint256 _initialSupply,
        string memory _name,
        string memory _symbol
    ) GovToken(_core, _vesting, _initialSupply, _name, _symbol) {}

    /**
        @notice TEST FUNCTION only to burn tokens
    */
    function burn(uint256 _amount) external {
        _burn(msg.sender, _amount);
    }
}
