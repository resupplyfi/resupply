// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { VestManager } from "./VestManager.sol";

contract VestManagerTEST is VestManager {

    constructor(
        address _core,
        address _token,
        address _burnAddress,
        address[3] memory _redemptionTokens, // PRISMA, yPRISMA, cvxPRISMA
        uint256 _timeUntilDeadline
    ) VestManager(_core, _token, _burnAddress, _redemptionTokens, _timeUntilDeadline) {}

    /**
        @notice TEST FUNCTION only to set merkle root
    */
    function setMerkleRoot(AllocationType _type, bytes32 _root) external {
        merkleRootByType[_type] = _root;
    }

    /**
        @notice TEST FUNCTION only to set user claim status
    */
    function setHasClaimed(address _account, AllocationType _type, bool _hasClaimed) external {
        hasClaimed[_account][_type] = _hasClaimed;
    }
}
