// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { ISimpleReceiver } from "../../../interfaces/ISimpleReceiver.sol";
import { CoreOwnable } from "../../../dependencies/CoreOwnable.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { IEmissionsController } from "../../../interfaces/IEmissionsController.sol";

contract SimpleReceiverFactory is CoreOwnable {
    using Clones for address;

    address public immutable emissionsController;
    address public implementation;
    address[] public receivers;

    event ReceiverDeployed(address indexed receiver, uint256 index);
    event ClaimerApproved(uint256 indexed index, address indexed claimer);
    event ImplementationSet(address indexed implementation);

    constructor(address _core, address _emissionsController, address _implementation) CoreOwnable(_core) {
        emissionsController = _emissionsController;
        implementation = _implementation;
        emit ImplementationSet(_implementation);
    }

    function setImplementation(address _implementation) external onlyOwner {
        implementation = _implementation;
        emit ImplementationSet(_implementation);
    }

    function deployNewReceiver(string memory _name, address[] memory _approvedClaimers) external onlyOwner returns (address receiver) {
        bytes32 nameHash = keccak256(bytes(_name));
        receiver = implementation.cloneDeterministic(nameHash);
        ISimpleReceiver(receiver).initialize(_name, _approvedClaimers);
        receivers.push(receiver);
        emit ReceiverDeployed(address(receiver), receivers.length - 1);
    }

    function getReceiverByName(string memory _name) external view returns (address receiver) {
        receiver = getDeterministicAddress(_name);
        return receiver.code.length > 0 ? receiver : address(0);
    }

    function getReceiversLength() external view returns (uint256) {
        return receivers.length;
    }

    function getDeterministicAddress(string memory _name) public view returns (address) {
        return Clones.predictDeterministicAddress(implementation, bytes32(keccak256(bytes(_name))));
    }

    function getReceiverId(address receiver) external view returns (uint256) {
        return IEmissionsController(emissionsController).receiverToId(receiver);
    }
}
