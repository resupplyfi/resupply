// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;


/*
Ownership
*/
contract Ownership{

    address public owner;
    address public pendingOwner;

    constructor(address _owner) {
          owner = _owner;
          emit OwnerChanged(_owner);
    }

    function _isOwner() internal virtual{
        require(owner == msg.sender, "!auth");
    }

    //set pending owner
    function setPendingOwner(address _po) external{
        _isOwner();
        pendingOwner = _po;
        emit SetPendingOwner(_po);
    }


    //claim ownership
    function acceptPendingOwner() external {
        require(pendingOwner != address(0) && msg.sender == pendingOwner, "!p_owner");

        owner = pendingOwner;
        pendingOwner = address(0);
        emit OwnerChanged(owner);
    }

    /* ========== EVENTS ========== */
    event SetPendingOwner(address indexed _address);
    event OwnerChanged(address indexed _address);
}