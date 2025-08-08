// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { VestManager } from "src/dao/tge/VestManager.sol";

// @dev This contract wraps the VestManger, giving ability to update values during testing
contract VestManagerHarness is VestManager {
    constructor(
        address _core,
        address _token,
        address _burnAddress,
        address[3] memory _redemptionTokens // PRISMA, yPRISMA, cvxPRISMA
    ) VestManager(_core, _token, _burnAddress, _redemptionTokens) {}

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
