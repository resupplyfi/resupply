// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { DelegatedOps } from '../dependencies/DelegatedOps.sol';
import { EpochTracker } from '../dependencies/EpochTracker.sol';
import { CoreOwnable } from '../dependencies/CoreOwnable.sol';
import { IGovStaker } from '../interfaces/IGovStaker.sol';
import { ICore } from '../interfaces/ICore.sol';
import { BytesLib } from "solidity-bytes-utils/contracts/BytesLib.sol";

interface IERC20 {
    function decimals() external view returns (uint256);
}
/**
    @title Resupply DAO Voting
    @author Resupply Finance (code inspired by Prisma Finance)
    @notice Primary ownership contract for all protocol contracts. Allows executing
            arbitrary function calls only after a required percentage of stakers
            have signalled in favor of performing the action.
 */
contract Voter is CoreOwnable, DelegatedOps, EpochTracker {

    uint256 public immutable TOKEN_DECIMALS;
    uint256 public constant VOTING_PERIOD = 1 weeks;
    uint256 public constant EXECUTION_DELAY = 1 days;
    uint256 public constant EXECUTION_DEADLINE = 3 weeks; // Includes VOTING_PERIOD
    uint256 public constant MIN_TIME_BETWEEN_PROPOSALS = 3 days;
    uint256 public constant MAX_PCT = 10000;
    uint256 public constant MAX_DESCRIPTION_BYTES = 384;

    IGovStaker public immutable staker;

    Proposal[] public proposalData;
    // Proposal ID -> payload
    mapping(uint256 id => Action[] payload) public proposalPayload;
    // Proposal ID -> description
    mapping(uint256 id => string description) public proposalDescription;
    // Record of user's vote: account -> ID -> vote
    mapping(address account => mapping(uint256 id => Vote vote)) public accountVoteWeights;
    // Record of last created proposal timestamp for a given account: account -> timestamp
    mapping(address account => uint256 timestamp) public latestProposalTimestamp;
    // Percent of total weight required to create a new proposal
    uint256 public minCreateProposalPct;
    // Percent of total weight that must vote for a proposal before it can be executed
    uint256 public quorumPct;

    event ProposalCreated(
        address indexed account,
        uint256 indexed id,
        Action[] payload,
        uint256 epoch,
        uint256 quorumWeight
    );
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalCancelled(uint256 indexed proposalId);
    event ProposalDescriptionUpdated(uint256 indexed proposalId, string description);
    event VoteCast(
        address indexed account,
        uint256 indexed id,
        uint256 weightYes,
        uint256 weightNo
    );
    event ProposalCreationMinPctSet(uint256 weight);
    event QuorumPctSet(uint256 pct);

    struct Proposal {
        uint16 epoch; // epoch which vote weights are based upon
        uint32 createdAt; // timestamp when the proposal was created
        uint40 quorumWeight; // amount of weight required for the proposal to become executable
        bool processed; // set to true once the proposal is processed
        Vote results; //  amount of weight currently voting on either side
    }

    struct Vote {
        uint40 weightYes;
        uint40 weightNo;
    }

    struct Action {
        address target;
        bytes data;
    }

    /**
        @notice Constructor for Voting contract
        @param _core Address of the core contract
        @param _staker Address of the staker contract
        @param _minCreateProposalPct Percent (in BPS) of total weight required to create a proposal
        @param _quorumPct Percent (in BPS) of total weight that must vote for a proposal before it can be executed
    */
    constructor(
        address _core,
        IGovStaker _staker,
        uint256 _minCreateProposalPct,
        uint256 _quorumPct
    ) CoreOwnable(_core) EpochTracker(_core) {
        staker = _staker;
        minCreateProposalPct = _minCreateProposalPct;
        quorumPct = _quorumPct;
        TOKEN_DECIMALS = IERC20(_staker.stakeToken()).decimals();
    }

    /**
        @notice The total number of votes created
     */
    function getProposalCount() external view returns (uint256) {
        return proposalData.length;
    }

    // @dev: Reverts in epoch 0 as proposals are not permitted
    function minCreateProposalWeight() public view returns (uint256) {
        uint256 epoch = getEpoch();
        epoch -= 1;
        uint256 totalWeight = staker.getTotalWeightAt(epoch);
        return (totalWeight * minCreateProposalPct) / MAX_PCT;
    }

    /**
        @notice Gets information on a specific proposal
        @dev Fetching the description can be expensive. 
            On chain integrations should consider accessing proposalData directly.
     */
    function getProposalData(uint256 id) external view returns (
        string memory description,
        uint256 epoch,
        uint256 createdAt,
        uint256 quorumWeight,
        uint256 weightYes,
        uint256 weightNo,
        bool processed,
        bool executable,
        Action[] memory payload
    ){
        Proposal memory proposal = proposalData[id];
        payload = proposalPayload[id];
        return (
            proposalDescription[id],
            proposal.epoch,
            proposal.createdAt,
            proposal.quorumWeight,
            proposal.results.weightYes,
            proposal.results.weightNo,
            proposal.processed,
            _canExecute(proposal),
            payload
        );
    }

    /**
        @notice Create a new proposal
        @param account Address of the account creating the proposal
        @param payload Tuple of [(target address, calldata), ... ] to be
                       executed if the proposal is passed.
        @param description Description text for the proposal
        @dev A proposal containing a proposal canceler action is required to be an independent single-action proposal.
     */
    function createNewProposal(address account, Action[] calldata payload, string calldata description) external callerOrDelegated(account) returns (uint256) {
        require(payload.length > 0, "Empty payload");
        require(
            latestProposalTimestamp[account] + MIN_TIME_BETWEEN_PROPOSALS < block.timestamp,
            "MIN_TIME_BETWEEN_PROPOSALS"
        );
        require(bytes(description).length <= MAX_DESCRIPTION_BYTES, "Description too long");
        if (_containsProposalCancelerPayload(payload)) require(payload.length == 1, "Payload length not 1");

        // week is set at -1 to the active week so that weights are finalized
        uint256 epoch = getEpoch();
        require(epoch > 0, "No proposals in first epoch");
        epoch -= 1;

        uint256 accountWeight = staker.getAccountWeightAt(account, epoch);
        require(accountWeight >= minCreateProposalWeight(), "Not enough weight to propose");

        uint256 totalWeight = staker.getTotalWeightAt(epoch) / 10 ** TOKEN_DECIMALS;
        uint40 quorumWeight = uint40((totalWeight * quorumPct) / MAX_PCT);
        require(quorumWeight > 0, "Too little stake weight");
        uint256 proposalId = proposalData.length;
        proposalData.push(
            Proposal({
                epoch: uint16(epoch),
                createdAt: uint32(block.timestamp),
                quorumWeight: quorumWeight,
                processed: false,
                results: Vote(0, 0)
            })
        );
        for (uint256 i = 0; i < payload.length; i++) {
            proposalPayload[proposalId].push(payload[i]);
        }
        proposalDescription[proposalId] = description;
        latestProposalTimestamp[account] = block.timestamp;
        emit ProposalCreated(account, proposalId, payload, epoch, quorumWeight);
        return proposalId;
    }

    /**
        @notice Vote fully in favor of a proposal
        @dev Each account can vote once per proposal. Uses full weight.
        @param account Address of the account voting
        @param id Proposal ID
     */
    function voteForProposal(address account, uint256 id) external callerOrDelegated(account) {
        _voteForProposal(account, id, MAX_PCT, 0);
    }
    /**
        @notice Vote in partial favor of a proposal
        @dev Each account can vote once per proposal. Uses full weight.
        @param account Address of the account voting
        @param id Proposal ID
        @param pctYes Percent of account's total weight to vote for
        @param pctNo Percent of account's total weight to vote against
     */
    function voteForProposal(address account, uint256 id, uint256 pctYes, uint256 pctNo) external callerOrDelegated(account) {
        require(pctYes + pctNo == MAX_PCT, "Sum of pcts must equal MAX_PCT");
        _voteForProposal(account, id, pctYes, pctNo);
    }

    function _voteForProposal(address account, uint256 id, uint256 pctYes, uint256 pctNo) internal {
        require(id < proposalData.length, "Invalid ID");
        Vote memory vote = accountVoteWeights[account][id];
        require(vote.weightYes + vote.weightNo == 0, "Already voted");

        Proposal memory proposal = proposalData[id];
        require(!proposal.processed, "Proposal already processed");
        require(proposal.createdAt + VOTING_PERIOD > block.timestamp, "Voting period has closed");

        // Reduce the account weight by the token decimals to help storage efficiency.
        uint256 accountWeight = staker.getAccountWeightAt(account, proposal.epoch) / 10 ** TOKEN_DECIMALS;
        require(accountWeight > 0, "Account weight is zero");

        vote.weightYes = uint40(accountWeight * pctYes / MAX_PCT);
        vote.weightNo = uint40(accountWeight * pctNo / MAX_PCT);
        accountVoteWeights[account][id] = vote;

        {
            Vote memory result = proposal.results;
            result.weightYes += vote.weightYes;
            result.weightNo += vote.weightNo;
            proposal.results = result;
        }
        
        proposalData[id] = proposal;
        emit VoteCast(account, id, vote.weightYes, vote.weightNo);
    }

    /**
        @notice Cancels a pending proposal
        @param id Proposal ID
        @dev Can cancel any time prior to execution
     */
    function cancelProposal(uint256 id) external onlyOwner {
        require(id < proposalData.length, "Invalid ID");
        require(!proposalData[id].processed, "Proposal already processed");
        if (proposalPayload[id].length == 1) require(!_containsProposalCancelerPayload(proposalPayload[id]), "Contains canceler payload");
        proposalData[id].processed = true;
        emit ProposalCancelled(id);
    }

    // @dev: inspects a payload to check if any actions contain a proposal canceler
    function _containsProposalCancelerPayload(Action[] memory payload) internal view returns (bool) {
        uint256 payloadLength = payload.length;
        for (uint256 i = 0; i < payloadLength; i++) {
            Action memory action = payload[i];
            bytes memory data = action.data;
            bytes4 selector;
            assembly {
                selector := mload(add(data, 32))
            }
            if (action.target == address(core) && selector == ICore.setOperatorPermissions.selector) {
                // 164 bytes is the length of a properly formed action which sets operator permissions on Core
                if (data.length < 164) return false;
                // Use BytesLib to slice the calldata, skipping the first 4 bytes (selector)
                bytes memory slicedData = BytesLib.slice(data, 4, data.length - 4);
                (, address target, bytes4 permissionSelector, , ) = abi.decode(slicedData, (address, address, bytes4, bool, address));
                if (permissionSelector != this.cancelProposal.selector) continue;
                if (target != address(this) && target != address(0)) continue;
                return true;
            }
        }
        return false;
    }

    /**
        @notice Execute a proposal's payload
        @dev Can only be called if the proposal has received sufficient vote weight,
             and has been active for at least `MIN_TIME_TO_EXECUTION`
        @param id Proposal ID
     */
    function executeProposal(uint256 id) external {
        require(id < proposalData.length, "Invalid proposalID");

        Proposal memory proposal = proposalData[id];
        require(_canExecute(proposal), "Proposal cannot be executed");
        proposalData[id].processed = true;

        Action[] storage payload = proposalPayload[id];
        uint256 payloadLength = payload.length;

        for (uint256 i = 0; i < payloadLength; i++) {
            ICore(core).execute(payload[i].target, payload[i].data);
        }
        emit ProposalExecuted(id);
    }

    function canExecute(uint256 id) external view returns (bool) {
        require(id < proposalData.length, "Invalid proposalID");
        return _canExecute(proposalData[id]);
    }

    function _canExecute(Proposal memory proposal) internal view returns (bool) {
        if (proposal.processed) return false;
        if (block.timestamp < proposal.createdAt + VOTING_PERIOD + EXECUTION_DELAY) return false;
        if (block.timestamp > proposal.createdAt + EXECUTION_DEADLINE) return false;

        // Ensure proposal has met quorum and received more weight in favor.
        if (!_quorumReached(proposal.quorumWeight, proposal.results)) return false;
        if (proposal.results.weightYes <= proposal.results.weightNo) return false;
        
        return true;
    }

    function quorumReached(uint256 id) external view returns (bool) {
        require(id < proposalData.length, "Invalid proposalID");
        Proposal memory proposal = proposalData[id];
        return _quorumReached(proposal.quorumWeight, proposal.results);
    }

    function _quorumReached(uint256 quorumWeight, Vote memory results) internal pure returns (bool) {
        return results.weightYes + results.weightNo >= quorumWeight;
    }

    /**
        @notice Set the minimum % of the total weight required to create a new proposal
     */
    function setMinCreateProposalPct(uint256 pct) external onlyOwner returns (bool) {
        require(pct > 0, "Too low");
        require(pct <= MAX_PCT, "Invalid value");
        minCreateProposalPct = pct;
        emit ProposalCreationMinPctSet(pct);
        return true;
    }

    /**
        @notice Set the required % of the total weight that must vote
                for a proposal in order to become executable
     */
    function setQuorumPct(uint256 pct) external onlyOwner returns (bool) {
        require(pct > 0, "Too low");
        require(pct <= MAX_PCT, "Invalid value");
        quorumPct = pct;
        emit QuorumPctSet(pct);
        return true;
    }


    /**
        @notice Overwrite the description text for an existing proposal
        @param id The ID of the proposal to update
        @param description New description text for the proposal
     */
    function updateProposalDescription(uint256 id, string calldata description) external onlyOwner {
        require(id < proposalData.length, "Invalid ID");
        require(bytes(description).length <= MAX_DESCRIPTION_BYTES, "Description too long");
        proposalDescription[id] = description;
        emit ProposalDescriptionUpdated(id, description);
    }
}