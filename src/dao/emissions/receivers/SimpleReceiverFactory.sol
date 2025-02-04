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
    mapping(bytes32 => address) public nameHashToReceiver;

    event ReceiverDeployed(address indexed receiver, address indexed implementation, uint256 index);
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

    /// @notice Deploys a new simple emissions receiver contract as a minimal proxy clone
    /// @dev Receivers must have unique names, unless deployed from different implementations
    /// @param _name The name of the receiver contract
    /// @param _approvedClaimers Array of addresses approved to claim emissions from this receiver
    /// @return receiver The address of the newly deployed receiver contract
    function deployNewReceiver(string memory _name, address[] memory _approvedClaimers) external onlyOwner returns (address receiver) {
        bytes32 nameHash = keccak256(bytes(_name));
        receiver = implementation.cloneDeterministic(nameHash);
        ISimpleReceiver(receiver).initialize(_name, _approvedClaimers);
        receivers.push(receiver);
        nameHashToReceiver[nameHash] = receiver;
        emit ReceiverDeployed(address(receiver), implementation, receivers.length - 1);
    }

    /// @dev Returns address(0) if no receiver is found.
    ///      If two receivers were deployed with the same name, only the latest is returned.
    function getReceiverByName(string memory _name) external view returns (address receiver) {
        receiver = nameHashToReceiver[keccak256(bytes(_name))];
    }

    function getReceiversLength() external view returns (uint256) {
        return receivers.length;
    }

    function getDeterministicAddress(string memory _name) public view returns (address) {
        return Clones.predictDeterministicAddress(implementation, bytes32(keccak256(bytes(_name))));
    }

    function getReceiverId(address _receiver) external view returns (uint256) {
        uint256 id = IEmissionsController(emissionsController).receiverToId(_receiver);
        if (id == 0) require(IEmissionsController(emissionsController).idToReceiver(id).receiver == _receiver, "!registered");
        return id;
    }
}
