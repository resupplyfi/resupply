// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { IGovToken } from "./IGovToken.sol";

interface IEmissionsController {
    // View functions
    function govToken() external view returns (IGovToken);
    function emissionsRate() external view returns (uint256);
    function emissionsPerEpoch(uint256 epoch) external view returns (uint256);
    function getEmissionsSchedule() external view returns (uint256[] memory);
    function getReceiverSplit(address receiver, uint256 epoch) external view returns (uint256);
    function getEpoch() external view returns (uint256);
    function receiverToId(address receiver) external view returns (uint256);
    function idToReceiver(uint256 id) external view returns (Receiver memory);
    function allocated(address receiver) external view returns (uint256);

    // State-changing functions
    function fetchEmissions() external returns (uint256);
    function setEmissionsSplits(uint256 _amount) external;
    function setEmissionsSchedule(uint256[] memory _rates, uint256 _epochsPer, uint256 _tailRate) external;
    function transferFromAllocation(address _recipient, uint256 _amount) external returns (uint256);

    // Events (if any)
    event EmissionsMinted(uint256 epoch, uint256 amount);
    event EmissionsSplitSet(address receiver, uint256 split);
    event EmissionsScheduleSet(uint256[] rates, uint256 epochsPer, uint256 tailRate);

    struct Receiver {
        bool active;
        address receiver;
        uint256 weight;
    }
}
