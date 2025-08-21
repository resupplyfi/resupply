// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title IResupplyPairImplementation
 * @notice Interface for ResupplyPairImplementation contract
 */
interface IResupplyPairImplementation {
    /// @notice Returns the creation code for ResupplyPair contracts
    /// @return The bytecode used to deploy new ResupplyPair instances
    function getCreationCode() external view returns (bytes memory);
    
    /// @notice Returns the version of this implementation
    /// @return _major Major version
    /// @return _minor Minor version  
    /// @return _patch Patch version
    function version() external pure returns (uint256 _major, uint256 _minor, uint256 _patch);
}