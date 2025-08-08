// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IGuardian {
    event GuardianSet(address indexed newGuardian);
    event PairPaused(address indexed pair);

    function registry() external view returns (address);
    function guardian() external view returns (address);
    function viewPermissions() external view returns (bool, bool, bool, bool, bool);

    function pauseAllPairs() external;
    function pausePair(address pair) external;
    function cancelProposal(uint256 proposalId) external;
    function setGuardian(address _guardian) external;
    function revertVoter() external;
    function recoverERC20(address _token) external;
}
