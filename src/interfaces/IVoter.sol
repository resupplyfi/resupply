// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IVoter {
    struct Vote {
        uint40 weightYes;
        uint40 weightNo;
    }

    struct Action {
        address target;
        bytes data;
    }

    struct Proposal {
        uint16 epoch;
        uint32 createdAt;
        uint40 quorumWeight;
        bool processed;
        Vote results;
    }

    event ProposalCreated(
        address indexed account,
        uint256 indexed id,
        Action[] payload,
        uint256 epoch,
        uint256 quorumWeight
    );
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalCancelled(uint256 indexed proposalId);
    event VoteCast(
        address indexed account,
        uint256 indexed id,
        uint256 weightYes,
        uint256 weightNo
    );
    event ProposalCreationMinPctSet(uint256 weight);
    event ProposalPassingPctSet(uint256 pct);
    event ProposalDescriptionUpdated(uint256 indexed proposalId, string description);
    
    function TOKEN_DECIMALS() external view returns (uint256);
    function VOTING_PERIOD() external view returns (uint256);
    function EXECUTION_DELAY() external view returns (uint256);
    function EXECUTION_DEADLINE() external view returns (uint256);
    function MIN_TIME_BETWEEN_PROPOSALS() external view returns (uint256);
    function MAX_PCT() external view returns (uint256);
    
    function staker() external view returns (address);
    function minCreateProposalPct() external view returns (uint256);
    function passingPct() external view returns (uint256);
    
    function accountVoteWeights(address account, uint256 id) external view returns (Vote memory);
    function latestProposalTimestamp(address account) external view returns (uint256);
    
    function getProposalCount() external view returns (uint256);
    function minCreateProposalWeight() external view returns (uint256);
    
    function getProposalData(uint256 id) external view returns (
        uint256 epoch,
        uint256 createdAt,
        uint256 quorumWeight,
        uint256 weightYes,
        uint256 weightNo,
        bool processed,
        bool executable,
        Action[] memory payload
    );
    
    function createNewProposal(address account, Action[] calldata payload) external returns (uint256);
    function voteForProposal(address account, uint256 id) external;
    function voteForProposal(address account, uint256 id, uint256 pctYes, uint256 pctNo) external;
    function cancelProposal(uint256 id) external;
    function executeProposal(uint256 id) external;
    function canExecute(uint256 id) external view returns (bool);
    function quorumReached(uint256 id) external view returns (bool);
    function setMinCreateProposalPct(uint256 pct) external returns (bool);
    function setPassingPct(uint256 pct) external returns (bool);
    function updateProposalDescription(uint256 id, string calldata description) external;
}