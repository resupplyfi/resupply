// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IGovStaker } from "../../interfaces/IGovStaker.sol";

contract SubDao is Ownable2Step {

    address public immutable core;
    bool public unstakingAllowed;
    string public name;
    IGovStaker public staker;
    
    event UnstakingAllowed(bool allowed);

    modifier noUnstaking {
        if (!unstakingAllowed) {
            uint256 pre = staker.balanceOf(address(this));
            require(msg.sender == owner(), "!owner");
            uint256 post = staker.balanceOf(address(this));
            require(post >= pre, "UnstakingForbidden");
        }
        _;
    }

    constructor(address _core, address _owner, string memory _name) {
        core = _core;
        name = _name;
        _transferOwnership(_owner);
    }

    function safeExecute(address target, bytes calldata data) external returns (bytes memory) {
        (bool success, bytes memory result) = _execute(target, data);
        require(success, "CallFailed");
        return result;
    }

    function execute(address target, bytes calldata data) external returns (bool, bytes memory) {
        return _execute(target, data);
    }

    function _execute(address target, bytes calldata data) internal onlyOwner noUnstaking returns (bool success, bytes memory result) {
        require(target != address(0), "Invalid target address");
        (success, result) = target.call(data);
    }

    function allowUnstaking(bool _allowed) external onlyOwner {
        require(msg.sender == core, "!core");
        unstakingAllowed = _allowed;
        emit UnstakingAllowed(_allowed);
    }
}