// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ResupplyPair } from "./ResupplyPair.sol";

/**
 * @title ResupplyPairImplementation
 * @notice Stores the creation code for ResupplyPair contracts
 * @dev This contract is deployed separately and referenced by ResupplyPairDeployer
 *      to enable clean upgrades by simply deploying a new implementation and updating the reference
 */
contract ResupplyPairImplementation {
    /// @notice The creation code for ResupplyPair contracts
    bytes public creationCode;
    
    constructor() {
        creationCode = type(ResupplyPair).creationCode;
    }
    
    /// @notice Returns the creation code for ResupplyPair contracts
    /// @return The bytecode used to deploy new ResupplyPair instances
    function getCreationCode() external view returns (bytes memory) {
        return creationCode;
    }
    
    /// @notice Returns the version of this implementation
    /// @return _major Major version
    /// @return _minor Minor version  
    /// @return _patch Patch version
    function version() external pure returns (uint256 _major, uint256 _minor, uint256 _patch) {
        return (1, 0, 0);
    }
}