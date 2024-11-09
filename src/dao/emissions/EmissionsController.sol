// SPDX-License-Identifier: MIT

pragma solidity ^0.8.22;

import { CoreOwnable } from "../../dependencies/CoreOwnable.sol";
import { EpochTracker } from "../../dependencies/EpochTracker.sol";
import { IGovToken } from "../../interfaces/IGovToken.sol";
import { IReceiver } from "../../interfaces/IReceiver.sol";

contract EmissionsController is CoreOwnable, EpochTracker {

    IGovToken immutable public govToken;
    uint256 public immutable BOOTSTRAP_EPOCHS;
    uint256 public emissionsRate;
    uint256 public constant PRECISION = 1e18;
    uint256 public constant BPS = 10_000;
    uint256[] private emissionsSchedule;
    uint256 public epochsPer;
    uint256 public tailRate;
    uint256 public unallocated;
    uint256 public lastMintEpoch;
    uint256 public lastEmissionsUpdate;
    uint256 public nextReceiverId;
    mapping(uint256 epoch => uint256 emissions) public emissionsPerEpoch;
    mapping(uint256 id => Receiver) public idToReceiver;
    mapping(address receiver => uint256 id) public receiverToId;
    mapping(address receiver => Allocated allocated) public allocated;

    modifier validReceiver(address _receiver) {
        if (receiverToId[_receiver] == 0) require(idToReceiver[0].receiver == _receiver, "Invalid receiver");
        _;
    }

    event EmissionsAllocated(address indexed receiver, uint256 indexed epoch, bool indexed unallocated, uint256 amount);
    event EmissionsRateUpdated(uint256 indexed epoch, uint256 rate);
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

    struct Allocated {
        uint56 lastFetchEpoch;
        uint200 amount;
    }

    constructor(
        address _core, 
        address _govToken, 
        uint256[] memory _emissionsSchedule,
        uint256 _epochsPer,
        uint256 _tailRate,
        uint256 _bootstrapEpochs
    ) CoreOwnable(_core) EpochTracker(_core) {
        govToken = IGovToken(_govToken);
        require(_emissionsSchedule.length > 0, "Missing emissions schedule");
        
        tailRate = _tailRate;
        epochsPer = _epochsPer;
        emissionsRate = _emissionsSchedule[_emissionsSchedule.length - 1];
        emissionsSchedule = _emissionsSchedule;
        emissionsSchedule.pop();
        BOOTSTRAP_EPOCHS = _bootstrapEpochs;
        if (_bootstrapEpochs > 0) {
            lastMintEpoch = _bootstrapEpochs;
            lastEmissionsUpdate = _bootstrapEpochs;
        }
    }


    function setReceiverWeights(uint256[] memory _receiverIds, uint256[] memory _newWeights) external onlyOwner {
        // TODO: Refactor this to be more efficient - 
        // only touch receivers that are specified in the calldata weights.
        // prevent duplicate receiver ids in the calldata array.

        require(_receiverIds.length == _newWeights.length, "Length mismatch");
        uint256 totalWeight = BPS;

        address[] memory receivers = new address[](_receiverIds.length);

        for (uint256 i = 0; i < _receiverIds.length; i++) {
            require(_newWeights[i] <= BPS, "Too much weight");
            Receiver memory receiver = idToReceiver[_receiverIds[i]];
            require(receiver.receiver != address(0), "Invalid receiver");
            if (_newWeights[i] > 0) require(receiver.active, "Receiver not active");
            for (uint256 j = 0; j < receivers.length; j++) {
                require(receivers[j] != receiver.receiver, "Duplicate receiver id");
            }
            receivers[i] = receiver.receiver;

            if (receiver.weight > 0) IReceiver(receiver.receiver).allocateEmissions();
            if (_newWeights[i] > receiver.weight) {
                totalWeight += (_newWeights[i] - receiver.weight);
            } else {
                totalWeight -= (receiver.weight - _newWeights[i]);
            }
            idToReceiver[_receiverIds[i]].weight = uint24(_newWeights[i]);
        }
        require(totalWeight == BPS, "Total weight must be 100%");

        emit ReceiverWeightsSet(_receiverIds, _newWeights);
    }

    function registerReceiver(address _receiver) external onlyOwner {
        require(_receiver != address(0), "Invalid receiver");
        uint256 _id = nextReceiverId++;
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
        allocated[_receiver] = Allocated({
            lastFetchEpoch: _id == 0 ? 0 : uint56(getEpoch()),
            amount: 0
        });
        receiverToId[_receiver] = _id;
        require(IReceiver(_receiver).getReceiverId() == _id, "bad interface"); // Require receiver to have this interface.
        emit ReceiverAdded(_id, _receiver);
    }

    /// @notice Deactivates a receiver, preventing them from receiving future emissions
    /// @dev All deactivations should be accompanied by a reallocation of its existing weight via setReceiverWeights().
    ///      If weights are not reallocated, emissions will accumulate as `unallocated`.
    /// @param _id The ID of the receiver to deactivate
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

    function transferFromAllocation(address _recipient, uint256 _amount) external {
        if (_amount > 0) {
            allocated[msg.sender].amount -= uint200(_amount);
            govToken.transfer(_recipient, _amount);
        }
    }


    function fetchEmissions() external validReceiver(msg.sender) returns (uint256) {
        return _fetchEmissions(msg.sender);
    }

    // dev: If no receivers are active, unallocated emissions will accumulate to next active receiver.
    function _fetchEmissions(address _receiver) internal returns (uint256) {
        uint256 epoch = getEpoch();
        if (epoch < BOOTSTRAP_EPOCHS) return 0;
        _mintEmissions(epoch); // bulk mints for the current epoch if not already done.
        Allocated memory _allocated = allocated[_receiver];
        if (_allocated.lastFetchEpoch >= epoch) return 0;
        Receiver memory receiver = idToReceiver[receiverToId[_receiver]];
        uint256 totalMinted;
        uint256 amount;
        while (_allocated.lastFetchEpoch < epoch) {
            _allocated.lastFetchEpoch++;
            amount = (
                receiver.weight * 
                emissionsPerEpoch[_allocated.lastFetchEpoch] /
                BPS
            );
            totalMinted += amount;
            emit EmissionsAllocated(_receiver, _allocated.lastFetchEpoch, !receiver.active, amount);
        }

        if (!receiver.active) {
            unallocated += totalMinted;
            allocated[_receiver] = _allocated;
            return 0;
        }
        
        _allocated.amount += uint200(totalMinted);
        allocated[_receiver] = _allocated; // write back to storage
        return totalMinted;
    }

    function _mintEmissions(uint256 epoch) internal {
        uint256 _lastMintEpoch = lastMintEpoch;
        if (epoch <= _lastMintEpoch) return;
        while (_lastMintEpoch < epoch) {
            if (++_lastMintEpoch < BOOTSTRAP_EPOCHS) continue;
            uint256 mintable = _calculateNewEmissions(_lastMintEpoch);
            if (mintable > 0) govToken.mint(address(this), mintable);
            emissionsPerEpoch[_lastMintEpoch] = mintable;
            if (nextReceiverId == 0) unallocated += mintable;
        }
        lastMintEpoch = epoch;
    }


    function _calculateNewEmissions(uint256 _epoch) internal returns (uint256) {
        uint256 _emissionsRate = emissionsRate;
        if (_epoch - lastEmissionsUpdate >= epochsPer) {
            uint256 len = emissionsSchedule.length;
            if (len > 0) {
                _emissionsRate = emissionsSchedule[len - 1];
                emissionsRate = _emissionsRate;
                emissionsSchedule.pop();
                emit EmissionsRateUpdated(_epoch, _emissionsRate);
            }
            else if (_emissionsRate != tailRate) {
                _emissionsRate = tailRate;
                emissionsRate = _emissionsRate;
                emit EmissionsRateUpdated(_epoch, _emissionsRate);
            }
            lastEmissionsUpdate = _epoch;
        }

        return (
            govToken.totalSupply() * 
            _emissionsRate * 
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

    function getSchedule() external view returns (uint256[] memory) {
        return emissionsSchedule;
    }

    function getScheduleLength() external view returns (uint256) {
        return emissionsSchedule.length;
    }
}