// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface ISimpleReceiver {
    function initialize(string memory _name, address[] memory _approvedClaimers) external;

    function getReceiverId() external view returns (uint256 id);

    function allocateEmissions() external returns (uint256 amount);

    function claimEmissions(address receiver) external returns (uint256 amount);

    function claimableEmissions() external view returns (uint256);

    function setApprovedClaimer(address claimer, bool approved) external;
}
