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
        uint56 lastAllocEpoch;
        uint200 amount;
    }

    /**
     * @notice Initializes the emissions controller contract
     * @param _core Address of the core contract
     * @param _govToken Address of the governance token that will be minted as emissions
     * @param _emissionsSchedule Array of emission rates, each representing a percentage with 18 decimals (1e18 = 100%)
     * @param _epochsPer Number of epochs between emission rate changes
     * @param _tailRate Final emission rate to use after schedule is exhausted
     * @param _bootstrapEpochs Number of epochs to delay the start of emissions
     * @dev the first epoch (0th) will never have emissions minted.
     */
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

    /**
     * @notice Sets the weights for receivers
     * @param _receiverIds Array of receiver IDs
     * @param _newWeights Array of new weights corresponding to the receiver IDs
     */
    function setReceiverWeights(uint256[] memory _receiverIds, uint256[] memory _newWeights) external onlyOwner {
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

            IReceiver(receiver.receiver).allocateEmissions(); // allocate according to old weight
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

    /**
     * @notice Registers a new receiver
     * @param _receiver Address of the receiver to register
     */
    function registerReceiver(address _receiver) external onlyOwner {
        require(_receiver != address(0), "Invalid receiver");
        uint256 _id = nextReceiverId++;
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
            lastAllocEpoch: _id == 0 ? 0 : uint56(getEpoch()),
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
        require(receiver.receiver != address(0), "Receiver not found");
        require(receiver.active, "Receiver not active");
        _fetchEmissions(receiver.receiver);
        idToReceiver[_id].active = false;
        emit ReceiverDisabled(_id);
    }

    function activateReceiver(uint256 _id) external onlyOwner {
        Receiver memory receiver = idToReceiver[_id];
        require(receiver.receiver != address(0), "Receiver not found");
        require(!receiver.active, "Receiver active");
        _fetchEmissions(receiver.receiver);
        idToReceiver[_id].active = true;
        emit ReceiverEnabled(_id);
    }

    function transferFromAllocation(address _recipient, uint256 _amount) external returns (uint256) {
        if (_amount > 0) {
            allocated[msg.sender].amount -= uint200(_amount);
            govToken.transfer(_recipient, _amount);
        }
        return _amount;
    }

    function fetchEmissions() external validReceiver(msg.sender) returns (uint256) {
        return _fetchEmissions(msg.sender);
    }

    // If no receivers are active, unallocated emissions will accumulate to next active receiver.
    function _fetchEmissions(address _receiver) internal returns (uint256) {
        uint256 epoch = getEpoch();
        if (epoch <= BOOTSTRAP_EPOCHS) return 0;
        _mintEmissions(epoch); // bulk mints for the current epoch if not already done.
        Allocated memory _allocated = allocated[_receiver];
        if (_allocated.lastAllocEpoch >= epoch) return 0;
        Receiver memory receiver = idToReceiver[receiverToId[_receiver]];
        uint256 totalMinted;
        uint256 amount;
        while (_allocated.lastAllocEpoch < epoch) {
            _allocated.lastAllocEpoch++;
            amount = (
                receiver.weight * 
                emissionsPerEpoch[_allocated.lastAllocEpoch] /
                BPS
            );
            totalMinted += amount;
            emit EmissionsAllocated(_receiver, _allocated.lastAllocEpoch, !receiver.active, amount);
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
            uint256 mintable = _calcEmissionsForEpoch(_lastMintEpoch);
            if (mintable > 0) govToken.mint(address(this), mintable);
            emissionsPerEpoch[_lastMintEpoch] = mintable;
            if (nextReceiverId == 0) unallocated += mintable;
        }
        lastMintEpoch = epoch;
    }


    function _calcEmissionsForEpoch(uint256 _epoch) internal returns (uint256) {
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
     * @dev rates must be in reverse order. Last item will be used first.
     * @dev All updates take effect in the epoch following the epoch in which the call is made.
     */
    function setEmissionsSchedule(uint256[] memory _rates, uint256 _epochsPer, uint256 _tailRate) external onlyOwner {
        require(_rates.length > 0, "Schedule length not > 0");
        require(_epochsPer > 0, "Invalid epochs per");
        for (uint256 i = 0; i < _rates.length; i++) {
            if (i == _rates.length - 1) break; // prevent index out of bounds
            require(_rates[i] <= _rates[i + 1], "Rates must decay"); // lower index must be <= than higher index
        }
        _mintEmissions(getEpoch()); // before updating, mint current epoch emissions at old rate
        require(_rates[0] > _tailRate, "Final rate not greater than tail rate");
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