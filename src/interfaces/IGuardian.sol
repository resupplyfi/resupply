// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IGuardian {
    event GuardianSet(address indexed newGuardian);
    event PairPaused(address indexed pair);

    function registry() external view returns (address);
    function guardian() external view returns (address);

    function pauseAllPairs() external;
    function pausePair(address pair) external;
    function cancelProposal(uint256 proposalId) external;
    function setGuardian(address _guardian) external;
    function revertVoter() external;
}
