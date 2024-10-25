// SPDX-License-Identifier: MIT

pragma solidity ^0.8.22;

import { CoreOwnable } from "../../dependencies/CoreOwnable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { EpochTracker } from "../../dependencies/EpochTracker.sol";
import { IGovToken } from "../../interfaces/IGovToken.sol";
import { IReceiver } from "../../interfaces/IReceiver.sol";

contract EmissionsController is CoreOwnable, EpochTracker {

    IGovToken immutable public govToken;
    uint256 public emissionsRate;
    uint256 public constant PRECISION = 1e18;
    uint256 public constant BPS = 10_000;
    uint256[] private emissionsSchedule;
    uint256 public epochsPer;
    uint256 public tailRate;
    uint256 public unallocated;
    uint256 public lastUpdateEpoch;
    uint256 public lastEmissionsUpdate;
    uint256 public nextReceiverId;
    uint256 constant YEAR = 31557600;
    mapping(uint256 => Receiver) public idToReceiver;
    mapping(address => uint256) public receiverToId;
    mapping(uint256 => uint256) public receiverWeight;
    mapping(uint256 => uint256) public receiverSplitPerEpoch;
    mapping(uint256 epoch => uint256 emissions) public emissionsPerEpoch;
    mapping(address => uint256) public receiverLastFetchEpoch;
    mapping(address => uint256) public allocated; // receiver => amount

    modifier validReceiver(address _receiver) {
        if (receiverToId[_receiver] == 0) require(idToReceiver[0].receiver == _receiver, "Invalid receiver");
        _;
    }

    event EmissionsFetched(address indexed receiver, uint256 indexed epoch, bool indexed unallocated, uint256 amount);
    event ReceiverDisabled(uint256 indexed id);
    event ReceiverEnabled(uint256 indexed id);
    event ReceiverAdded(uint256 indexed id, address indexed receiver);
    event ReceiverWeightsSet(uint256[] receiverIds, uint256[] weights);
    event UnallocatedRecovered(address indexed recipient, uint256 amount);

    struct Receiver {
        bool active;
        address receiver;
        uint88 weight;
    }

    constructor(address _core, address _govToken, uint256[] memory _emissionsSchedule, uint256 _epochsPer) CoreOwnable(_core) EpochTracker(_core) {
        govToken = IGovToken(_govToken);
        emissionsSchedule = _emissionsSchedule;
        tailRate = 1e16; // 2%
        lastEmissionsUpdate = 0;
        epochsPer = _epochsPer;
    }


    function setReceiverWeights(uint256[] memory _receiverIds, uint256[] memory _weights) external onlyOwner {
        require(_receiverIds.length == _weights.length, "Length mismatch");
        uint256 totalWeight;

        // Clear all existing weights and fetch any unclaimed emissions
        for (uint256 i = 0; i < nextReceiverId; i++) {
            if (receiverWeight[i] > 0) {
                IReceiver(idToReceiver[i].receiver).fetchAllocatedEmissions();
                receiverWeight[i] = 0;
            }
        }

        // Set new weights
        for (uint256 i = 0; i < _receiverIds.length; i++) {
            require(_receiverIds[i] < nextReceiverId, "Invalid receiver ID");
            if (_weights[i] > 0) {
                require(idToReceiver[_receiverIds[i]].active, "Receiver not active");
            }
            receiverWeight[_receiverIds[i]] = _weights[i];
            totalWeight += _weights[i];
        }

        require(totalWeight == BPS, "Total weight must be 100%");
        emit ReceiverWeightsSet(_receiverIds, _weights);
    }

    function addReceiver(address _receiver) external onlyOwner {
        require(_receiver != address(0), "Invalid receiver");
        uint256 id = receiverToId[_receiver];
        require(idToReceiver[id].receiver == address(0), "Receiver already added.");
        uint _nextId = nextReceiverId;
        idToReceiver[_nextId] = Receiver({
            active: true,
            receiver: _receiver,
            weight: 0
        });
        receiverToId[_receiver] = _nextId;
        nextReceiverId++;
        emit ReceiverAdded(_nextId, _receiver);
    }

    function disableReceiver(uint256 _id) external onlyOwner {
        Receiver memory receiver = idToReceiver[_id];
        require(receiver.active, "Receiver not active");
        require(receiver.receiver != address(0), "Receiver not found.");
        idToReceiver[_id].active = false;
        emit ReceiverDisabled(_id);
    }

    function enableReceiver(uint256 _id) external onlyOwner {
        Receiver memory receiver = idToReceiver[_id];
        require(!receiver.active, "Receiver already active");
        require(receiver.receiver != address(0), "Receiver not found.");
        idToReceiver[_id].active = true;
        emit ReceiverEnabled(_id);
    }

    function fetchEmissions() external validReceiver(msg.sender) returns (uint256) {
        return _fetchEmissions(msg.sender);
    }

    function _fetchEmissions(address _receiver) internal returns (uint256) {
        uint256 epoch = getEpoch();
        _mintEmissions(epoch);
        uint256 lastFetch = receiverLastFetchEpoch[_receiver];
        if (lastFetch >= epoch) return 0;
        Receiver memory receiver = idToReceiver[receiverToId[_receiver]];
        uint256 totalEmissionsForReceiver;
        uint256 amount;
        while (lastFetch < epoch) {
            lastFetch++;
            uint256 receiverId = receiverToId[_receiver];
            amount = (
                receiverWeight[receiverId] * 
                emissionsPerEpoch[lastFetch] /
                BPS
            );
            totalEmissionsForReceiver += amount;
            emit EmissionsFetched(_receiver, lastFetch, receiver.active, amount);
        }
        receiverLastFetchEpoch[msg.sender] = epoch;
        if (receiver.active) {
            allocated[_receiver] += totalEmissionsForReceiver;
            return totalEmissionsForReceiver;
        }
        else {
            unallocated += emissionsPerEpoch[lastFetch];
            return 0;
        }
    }

    function transferFromAllocation(address _recipient, uint256 _amount) external {
        if (_amount > 0) {
            allocated[msg.sender] -= _amount;
            govToken.transfer(_recipient, _amount);
        }
    }


    function _mintEmissions(uint256 epoch) internal {
        uint256 _lastUpdateEpoch = lastUpdateEpoch;
        if (epoch <= _lastUpdateEpoch) return;
        while (_lastUpdateEpoch < epoch) { // dev: no emissions in the 0th epoch
            _lastUpdateEpoch++;
            if (_lastUpdateEpoch - lastEmissionsUpdate >= epochsPer) {
                uint256 mintable = _calculateNewEmissions();
                if (mintable > 0) govToken.mint(address(this), mintable);
                // unallocated += mintable; ?
                emissionsPerEpoch[_lastUpdateEpoch] = mintable;
                lastEmissionsUpdate = _lastUpdateEpoch;
            }
        }
        lastUpdateEpoch = epoch;
    }


    function _calculateNewEmissions() internal returns (uint256) {
        uint256 len = emissionsSchedule.length;
        if (len > 0) {
            emissionsRate = emissionsSchedule[len - 1];
            emissionsSchedule.pop();
        }
        else {
            emissionsRate = tailRate;
        }

        // Epochly mintable emissions
        return (
            govToken.totalSupply() * 
            emissionsRate * 
            epochLength /
            YEAR /
            PRECISION
        );
    }

    /**
     * @notice Sets the emissions schedule and epochs per schedule item
     * @param _rates An array of inflation rates expressed as annual pct of total supply (100% = 1e18)
     * @param _epochsPer Number of epochs each schedule item lasts
     * @dev rates should be in reverse order. Last item will be used first.
     */
    function setEmissionsSchedule(uint256[] memory _rates, uint256 _epochsPer, uint256 _tailRate) external onlyOwner {
        require(_rates.length > 0, "Schedule must have at least one item");
        if (_rates.length == 1) {
            require(_epochsPer > 0, "Invalid epochs per");
        }
        for (uint256 i = 0; i < _rates.length - 1; i++) {
            if (i == _rates.length - 1) break;
            require(_rates[i] > _rates[i + 1], "Rates must decay");
        }
        require(_rates[_rates.length - 1] > _tailRate, "Final rate <= tail rate");
        emissionsSchedule = _rates;
        epochsPer = _epochsPer;
        tailRate = _tailRate;
    }

    function recoverUnallocated(address _recipient) external onlyOwner {
        govToken.transfer(_recipient, unallocated);
        emit UnallocatedRecovered(_recipient, unallocated);
    }

    function getEmissionsSchedule() external view returns (uint256[] memory) {
        return emissionsSchedule;
    }
}
