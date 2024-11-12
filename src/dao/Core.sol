// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { IAuthHook } from '../interfaces/IAuthHook.sol';
import { Address } from '@openzeppelin/contracts/utils/Address.sol';

/**
    @title Core
    @author Prisma Finance (with edits by Relend.fi)
    @notice Single source of truth for system-wide values and contract ownership.

            Ownership of this contract should be the DAO via `Voting`.
            Other ownable contracts inherit their ownership from this contract
            using `Ownable`.
 */
contract Core {
    using Address for address;

    address public voter;

    uint256 public immutable startTime;
    uint256 public immutable epochLength;
    // System-wide pause. When true, disables trove adjustments across all collaterals.
    bool private paused;

    // permission for callers to execute arbitrary calls via this contract's `execute` function
    mapping(address caller => mapping(address target => mapping(bytes4 selector => OperatorAuth auth))) public operatorPermissions;

    event VoterSet(address indexed newVoter);
    event ProtocolPaused(bool indexed paused);
    event OperatorExecuted(address indexed caller, address indexed target, bytes data);
    event OperatorSet(address indexed caller, address indexed target, bool authorized, bytes4 selector, IAuthHook authHook);

    struct Action {
        address target;
        bytes data;
    }

    struct OperatorAuth {
        bool authorized;    // uint8
        IAuthHook hook;
    }

    modifier onlyCore() {
        require(msg.sender == address(this), "!core");
        _;
    }

    constructor(address _voter, uint256 _epochLength) {
        require(_epochLength > 0, "Epoch length must be greater than 0");
        require(_epochLength <= 100 days, "Epoch length must be less than 100 days");
        startTime = (block.timestamp / _epochLength) * _epochLength;
        epochLength = _epochLength;
        voter = _voter;
        emit VoterSet(_voter);
    }

    /**
        @notice Execute an arbitrary function call using this contract
        @dev Callable via the voter, or any operator with explicit permission.       
     */
    function execute(address target, bytes calldata data) external returns (bytes memory) {
        if (msg.sender == voter) return target.functionCall(data);
        bytes4 selector = bytes4(data[:4]);
        OperatorAuth memory auth = operatorPermissions[msg.sender][address(0)][selector];
        if (!auth.authorized) {
            auth = operatorPermissions[msg.sender][target][selector];
        }
        require(auth.authorized, "!authorized");
        if (auth.hook != IAuthHook(address(0))) require(auth.hook.preHook(msg.sender, target, data), "Auth PreHook Failed");
        bytes memory result = target.functionCall(data);
        if (auth.hook != IAuthHook(address(0))) require(auth.hook.postHook(result, msg.sender, target, data), "Auth PostHook Failed");
        emit OperatorExecuted(msg.sender, target, data);
        return result;
    }

    /**
        @notice Grant or revoke permission for `caller` to call one or more
                functions on `target` via this contract.
        @dev Setting `target` to the zero address allows for global authorization of
             `caller` to use `selector` on any target.
     */
    function setOperatorPermissions(
        address caller,
        address target,
        bytes4 selector,
        bool authorized,
        IAuthHook authHook
    ) onlyCore public {
        operatorPermissions[caller][target][selector] = OperatorAuth(authorized, authHook);
        emit OperatorSet(caller, target, authorized, selector, authHook);
    }

    function setVoter(address newVoter) external onlyCore {
        voter = newVoter;
        emit VoterSet(newVoter);
    }

    /**
     * @notice Sets the global pause state of the protocol
     *         Pausing is used to mitigate risks in exceptional circumstances.
     */
    function pauseProtocol() public onlyCore {
        require(!paused, "Already Paused");
        paused = true;
        emit ProtocolPaused(true);
    }

    function unpauseProtocol() public onlyCore {
        require(paused, "Already Unpaused");
        paused = false;
        emit ProtocolPaused(false);
    }

    function isProtocolPaused() external view returns (bool) {
        return paused;
    }
}