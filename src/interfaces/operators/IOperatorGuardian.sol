// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IOperatorGuardian {
    function setRegistryAddress(string memory key, address value) external;
    function setGuardian(address guardian) external;
    function pauseAllPairs() external;
    function pausePair(address pair) external;
    function cancelProposal(uint256 proposalId) external;
    function updateProposalDescription(uint256 proposalId, string calldata newDescription) external;
    function revertVoter() external;
    function viewPermissions() external view returns (bool, bool, bool, bool, bool);
    function guardian() external view returns (address);
}