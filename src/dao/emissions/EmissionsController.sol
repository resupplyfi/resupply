// SPDX-License-Identifier: MIT

pragma solidity ^0.8.22;

import { CoreOwnable } from "../../dependencies/CoreOwnable.sol";
import { EpochTracker } from "../../dependencies/EpochTracker.sol";
import { IGovToken } from "../../interfaces/IGovToken.sol";
import { IReceiver } from "../../interfaces/IReceiver.sol";

contract EmissionsController is CoreOwnable, EpochTracker {

    IGovToken immutable public govToken;
    uint256 public immutable BOOTSTRAP_EPOCHS; // dev: number of epochs before emissions begin
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
    mapping(uint256 id => Receiver) public idToReceiver;
    mapping(address receiver => uint256 id) public receiverToId;
    mapping(uint256 epoch => uint256 emissions) public emissionsPerEpoch;
    mapping(address receiver => uint256 lastFetchEpoch) public receiverLastFetchEpoch;
    mapping(address receiver => uint256 allocated) public allocated; // receiver => amount

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
        uint24 weight;
    }

    constructor(
        address _core, 
        address _govToken, 
        uint256[] memory _emissionsSchedule, 
        uint256 _epochsPer,
        uint256 _bootstrapEpochs
    ) CoreOwnable(_core) EpochTracker(_core) {
        govToken = IGovToken(_govToken);
        require(_emissionsSchedule.length > 0, "Missing emissions schedule");
        emissionsSchedule = _emissionsSchedule;
        tailRate = 1e16; // 2%
        epochsPer = _epochsPer;
        emissionsRate = _emissionsSchedule[_emissionsSchedule.length - 1];
        BOOTSTRAP_EPOCHS = _bootstrapEpochs;
        if (_bootstrapEpochs > 0) {
            lastUpdateEpoch = _bootstrapEpochs - 1;
        }
    }


    function setReceiverWeights(uint256[] memory _receiverIds, uint256[] memory _weights) external onlyOwner {
        // TODO: Refactor this to be more efficient - 
        // only touch receivers that are specified in the calldata weights.

        require(_receiverIds.length == _weights.length, "Length mismatch");
        uint256 totalWeight;

        // Iterate through all receivers in storage and clear any existing
        // weights + fetch any unclaimed emissions
        uint256 len = nextReceiverId;
        Receiver storage receiver;
        for (uint256 i = 0; i < len; i++) {
            receiver = idToReceiver[i];
            if (receiver.weight > 0) {
                IReceiver(receiver.receiver).allocateEmissions();
                receiver.weight = 0;
            }
        }

        // Set new weights
        for (uint256 i = 0; i < _receiverIds.length; i++) {
            require(_receiverIds[i] < nextReceiverId, "Invalid receiver ID");
            receiver = idToReceiver[_receiverIds[i]];
            require(receiver.receiver != address(0), "Invalid receiver");
            if (_weights[i] > 0) {
                require(receiver.active, "Receiver not active");
            }
            receiver.weight = uint24(_weights[i]);
            totalWeight += _weights[i];
        }

        require(totalWeight == BPS, "Total weight must be 100%");
        emit ReceiverWeightsSet(_receiverIds, _weights);
    }

    function registerReceiver(address _receiver) external onlyOwner {
        require(_receiver != address(0), "Invalid receiver");
        uint256 _id = nextReceiverId;
        // if foundId is zero, it either exists as id 0, or not yet registered.
        if (_id > 0) {
            require(
                idToReceiver[receiverToId[_receiver]].receiver != _receiver, 
                "Receiver already added."
            );
        }
        idToReceiver[_id] = Receiver({
            active: true,
            receiver: _receiver,
            weight: _id == 0 ? 10_000 : 0 // first receiver gets 100%
        });
        receiverToId[_receiver] = _id;
        nextReceiverId++;
        require(IReceiver(_receiver).getReceiverId() == _id, "bad interface"); // Require receiver to have this interface.
        emit ReceiverAdded(_id, _receiver);
    }

    // dev: all deactivations should be accompanied by a reallocation of existing weight. 
    // If not, emissions will accumulate to unallocated.
    function deactivateReceiver(uint256 _id) external onlyOwner {
        Receiver memory receiver = idToReceiver[_id];
        require(receiver.active, "Receiver not active");
        require(receiver.receiver != address(0), "Receiver not found.");
        _fetchEmissions(receiver.receiver);
        idToReceiver[_id].active = false;
        emit ReceiverDisabled(_id);
    }

    function activateReceiver(uint256 _id) external onlyOwner {
        Receiver memory receiver = idToReceiver[_id];
        require(!receiver.active, "Receiver already active");
        require(receiver.receiver != address(0), "Receiver not found.");
        _fetchEmissions(receiver.receiver);
        idToReceiver[_id].active = true;
        emit ReceiverEnabled(_id);
    }

    function fetchEmissions() external validReceiver(msg.sender) returns (uint256) {
        return _fetchEmissions(msg.sender);
    }

    // dev: If receivers are not active, unallocated emissions will accumulate
    function _fetchEmissions(address _receiver) internal returns (uint256) {
        uint256 epoch = getEpoch();
        _mintEmissions(epoch);
        uint256 lastFetch = receiverLastFetchEpoch[_receiver];
        if (lastFetch >= epoch) return 0;
        Receiver memory receiver = idToReceiver[receiverToId[_receiver]];
        uint256 totalMinted;
        uint256 amount;
        while (lastFetch < epoch) {
            lastFetch++;
            amount = (
                receiver.weight * 
                emissionsPerEpoch[lastFetch] /
                BPS
            );
            totalMinted += amount;
            emit EmissionsFetched(_receiver, lastFetch, receiver.active, amount);
        }
        receiverLastFetchEpoch[msg.sender] = epoch;
        if (!receiver.active) {
            unallocated += totalMinted;
            return 0;
        }
        allocated[_receiver] += totalMinted;
        return totalMinted;
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
        if (epoch < BOOTSTRAP_EPOCHS) return;
        while (_lastUpdateEpoch < epoch) { 
            _lastUpdateEpoch++;
            bool shouldUpdateRate = _lastUpdateEpoch - lastEmissionsUpdate >= epochsPer;
            uint256 mintable = _calculateNewEmissions(shouldUpdateRate, _lastUpdateEpoch);
            if (mintable > 0) govToken.mint(address(this), mintable);
            emissionsPerEpoch[_lastUpdateEpoch] = mintable;
            if (nextReceiverId == 0) unallocated += mintable;
        }
        lastUpdateEpoch = epoch;
    }


    function _calculateNewEmissions(bool _shouldUpdateRate, uint256 _epoch) internal returns (uint256) {
        if (_shouldUpdateRate) {
            uint256 len = emissionsSchedule.length;
            if (len > 0) {
                emissionsRate = emissionsSchedule[len - 1];
                emissionsSchedule.pop();
            }
            else {
                emissionsRate = tailRate;
            }
            lastEmissionsUpdate = _epoch;
        }

        return (
            govToken.totalSupply() * 
            emissionsRate * 
            epochLength /
            365 days /
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

    /**
     * @notice Recovers any unallocated emissions and sends them to the specified recipient
     * @param _recipient Address to send the unallocated emissions to
     * @dev Can only be called by the owner (Core contract)
     * @dev Resets unallocated balance to 0 after transfer
     * @dev Emits UnallocatedRecovered event
     */
    function recoverUnallocated(address _recipient) external onlyOwner {
        uint256 _unallocated = unallocated;
        unallocated = 0;
        govToken.transfer(_recipient, _unallocated);
        emit UnallocatedRecovered(_recipient, _unallocated);
    }

    function getEmissionsSchedule() external view returns (uint256[] memory) {
        return emissionsSchedule;
    }
}
