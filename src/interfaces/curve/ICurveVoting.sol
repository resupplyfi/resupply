// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface ICurveVoting{
    function newVote(bytes calldata _executionScript, string calldata _metadata, bool _castVote, bool _executesIfDecided) external returns (uint256 voteId);
    function votePct(uint256 _voteId, uint256 _yeaPct, uint256 _nayPct, bool _executesIfDecided) external;
    function executeVote(uint256 _voteId) external;
    function execute(address _target, uint256 _ethValue, bytes calldata _data) external; //agent execute
    function getVote(uint256 _voteId)
        external
        view
        returns (
            bool open,
            bool executed,
            uint64 startDate,
            uint64 snapshotBlock,
            uint64 supportRequired,
            uint64 minAcceptQuorum,
            uint256 yea,
            uint256 nay,
            uint256 votingPower,
            bytes memory script
        );
    function canExecute(uint256 _voteId) external view returns (bool);
    function votesLength() external view returns (uint256);
}