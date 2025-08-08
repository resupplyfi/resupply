// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
    @title Delegated Operations
    @author Prisma Finance (with edits by Resupply Finance)
    @notice Allows delegation to specific contract functionality. Useful for creating
            wrapper contracts to bundle multiple interactions into a single call.
 */
contract DelegatedOps {
    event DelegateApprovalSet(address indexed account, address indexed delegate, bool isApproved);

    mapping(address owner => mapping(address caller => bool isApproved)) public isApprovedDelegate;

    modifier callerOrDelegated(address _account) {
        require(msg.sender == _account || isApprovedDelegate[_account][msg.sender], "!CallerOrDelegated");
        _;
    }

    function setDelegateApproval(address _delegate, bool _isApproved) external {
        isApprovedDelegate[msg.sender][_delegate] = _isApproved;
        emit DelegateApprovalSet(msg.sender, _delegate, _isApproved);
    }
}
