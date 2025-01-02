// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IEmissionsController } from "../../../interfaces/IEmissionsController.sol";
import { CoreOwnable } from "../../../dependencies/CoreOwnable.sol";


contract SimpleReceiver is CoreOwnable {

    IEmissionsController public immutable emissionsController;
    IERC20 public immutable govToken;
    string public name;
    mapping(address => bool) public approvedClaimers;

    event ClaimerApproved(address indexed claimer, bool indexed approved);

    modifier onlyOwnerOrApprovedClaimers() {
        require(approvedClaimers[msg.sender] || msg.sender == owner(), "Not approved claimer");
        _;
    }

    constructor(address _core, address _emissionsController) CoreOwnable(_core) {
        emissionsController = IEmissionsController(_emissionsController);
        govToken = IERC20(address(emissionsController.govToken()));
    }

    function initialize(string memory _name, address[] memory _approvedClaimers) external {
        require(bytes(_name).length != 0, "Name cannot be empty");
        require(bytes(name).length == 0, "Already initialized");
        name = _name;
        for (uint256 i = 0; i < _approvedClaimers.length; i++) {
            approvedClaimers[_approvedClaimers[i]] = true;
            emit ClaimerApproved(_approvedClaimers[i], true);
        }
    }


    function getReceiverId() external view returns (uint256 id) {
        id = emissionsController.receiverToId(address(this));
        if (id == 0) require(emissionsController.idToReceiver(id).receiver == address(this), "!registered");
    }

    function allocateEmissions() external returns (uint256 amount) {
        amount = emissionsController.fetchEmissions();
    }

    function claimEmissions(address receiver) external onlyOwnerOrApprovedClaimers returns (uint256 amount) {
        emissionsController.fetchEmissions();
        (, uint256 allocated) = emissionsController.allocated(address(this));
        return emissionsController.transferFromAllocation(receiver, allocated);
    }

    // Notice: Get the estimated allocation of emissions for this receiver
    // dev: The return value does not include any pending emissions that have not yet been minted.
    //      To ensure the pending amount is included, first call `allocateEmissions()`
    function claimableEmissions() external view returns (uint256) {
        (, uint256 allocated) = emissionsController.allocated(address(this));
        return allocated;
    }

    function setApprovedClaimer(address claimer, bool approved) external onlyOwner {
        approvedClaimers[claimer] = approved;
        emit ClaimerApproved(claimer, approved);
    }
}
