// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IGuardian {
    event GuardianSet(address indexed newGuardian);
    event PairPaused(address indexed pair);
    event GuardedRegistryKeySet(string key, bool indexed guarded);

    struct Permissions {
        bool pauseAllPairs;
        bool cancelProposal;
        bool updateProposalDescription;
        bool revertVoter;
        bool setRegistryAddress;
        bool revokeSwapperApprovals;
    }

    function registry() external view returns (address);
    function guardian() external view returns (address);
    function viewPermissions() external view returns (bool, bool, bool, bool, bool);
    // function viewPermissions() external view returns (Permissions memory);
    function hasPermission(address target, bytes4 selector) external view returns (bool);
    function guardedRegistryKey(string memory key) external view returns (bool);

    function pauseAllPairs() external;
    function pausePair(address pair) external;
    function cancelProposal(uint256 proposalId) external;
    function setGuardian(address _guardian) external;
    function revertVoter() external;
    function recoverERC20(address _token) external;
    function revokeSwapperApprovals(string calldata key) external;
    function setGuardedRegistryKey(string memory _key, bool _guarded) external;
}
