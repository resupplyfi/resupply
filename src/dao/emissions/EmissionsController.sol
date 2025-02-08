// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { CoreOwnable } from "../../dependencies/CoreOwnable.sol";
import { EpochTracker } from "../../dependencies/EpochTracker.sol";
import { IGovToken } from "../../interfaces/IGovToken.sol";
import { IReceiver } from "../../interfaces/IReceiver.sol";

contract EmissionsController is CoreOwnable, EpochTracker {

    /// @notice Address of the governance token that will be minted as emissions
    IGovToken immutable public govToken;
    
    /// @notice Current epoch emission rate, represented as a percentage with 18 decimals (1e18 = 100%)
    /// @dev Percentage corresponds to % of total token supply to inflate by yearly
    uint256 public emissionsRate;
    
    /// @notice Array of emission rates, each representing a percentage with 18 decimals (1e18 = 100%)
    /// @dev Rates are in reverse order - meaning the last item will be used first. 
    uint256[] internal emissionsSchedule;
    
    /// @notice Number of epochs between emission rate changes
    uint256 public epochsPer;
    
    /// @notice Final emission rate to use after emissionsSchedule is exhausted
    uint256 public tailRate;
    
    /// @notice Current emissions that have been minted but unallocated to a receiver.
    /// @dev Can only be swept out by owner to then be re-allocated.
    uint256 public unallocated;
    
    /// @notice Most recent epoch in which we minted emissions.
    /// @dev If we have a bootstrap period, this is set to the first epoch beyond the bootstrap on deployment.
    uint256 public lastMintEpoch;
    
    /// @notice Most recent epoch in which emissions rate was updated.
    /// @dev If we have a bootstrap period, this is set to the first epoch beyond the bootstrap on deployment.
    uint256 public lastEmissionsUpdate;
    
    /// @notice ID that our next registered receiver will be assigned.
    uint256 public nextReceiverId;
    
    /// @notice Look up emissions in a given epoch number.
    mapping(uint256 epoch => uint256 emissions) public emissionsPerEpoch;
    
    /// @notice Look up of a receiver's corresponding ReceiverInfo struct using the receiver's ID.
    mapping(uint256 id => ReceiverInfo) public idToReceiver;
    
    /// @notice Look up a receiver's ID number using its address.
    mapping(address receiver => uint256 id) public receiverToId;
    
    /// @notice Look up a receiver's Allocated struct using its address.
    mapping(address receiver => Allocated allocated) public allocated;
    
    /// @notice Number of epochs to delay the start of emissions.
    /// @dev Coincidentally, this number will be the first epoch with emissions.
    uint256 public immutable BOOTSTRAP_EPOCHS;
    
    uint256 internal constant PRECISION = 1e18;
    uint256 internal constant BPS = 10_000;

    modifier validReceiver(address _receiver) {
        require(isRegisteredReceiver(_receiver), "Invalid receiver");
        _;
    }

    event EmissionsAllocated(address indexed receiver, uint256 indexed epoch, bool indexed unallocated, uint256 amount);
    event EmissionsRateUpdated(uint256 indexed epoch, uint256 rate);
    event ReceiverDeactivated(uint256 indexed id);
    event ReceiverActivated(uint256 indexed id);
    event ReceiverAdded(uint256 indexed id, address indexed receiver);
    event ReceiverWeightsSet(uint256[] receiverIds, uint256[] weights);
    event UnallocatedRecovered(address indexed recipient, uint256 amount);
    event EmissionsScheduleSet(uint256[] rates, uint256 epochsPer, uint256 tailRate);

    struct ReceiverInfo{
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
     * @dev The first epoch (0th) will never have emissions minted.
     */
    constructor(
        address _core, 
        address _govToken, 
        uint256[] memory _emissionsSchedule,
        uint256 _epochsPer,
        uint256 _tailRate,
        uint256 _bootstrapEpochs
    ) CoreOwnable(_core) EpochTracker(_core) {
        require(_emissionsSchedule.length > 0 && _epochsPer > 0, "Must be >0");
        require(_emissionsSchedule[0] >= _tailRate, "Final rate less than tail rate");
        for (uint256 i = 0; i < _emissionsSchedule.length - 1; i++) {
            require(_emissionsSchedule[i] <= _emissionsSchedule[i + 1], "Rate greater than predecessor");
        }
        govToken = IGovToken(_govToken);
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

        for (uint256 i; i < _receiverIds.length; ++i) {
            ReceiverInfo memory receiver = idToReceiver[_receiverIds[i]];
            require(receiver.receiver != address(0), "Invalid receiver");
            if (_newWeights[i] > 0) require(receiver.active, "Receiver not active");
            for (uint256 j; j < receivers.length; ++j) {
                require(receivers[j] != receiver.receiver, "Duplicate receiver id");
            }
            receivers[i] = receiver.receiver;
            _fetchEmissions(receiver.receiver); // allocate according to old weight
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
        require(
            idToReceiver[receiverToId[_receiver]].receiver != _receiver, 
            "Receiver already added."
        );
        idToReceiver[_id] = ReceiverInfo({
            active: true,
            receiver: _receiver,
            weight: uint24(_id == 0 ? BPS : 0) // first receiver gets 100%
        });
        allocated[_receiver] = Allocated({
            // in case we don't register a receiver until after bootstrap, hardcode first receiver to epoch 0
            lastAllocEpoch: _id == 0 ? 0 : uint56(getEpoch()),
            amount: 0
        });
        receiverToId[_receiver] = _id;
        require(IReceiver(_receiver).getReceiverId() == _id, "bad interface"); // Require receiver to have this interface.
        emit ReceiverAdded(_id, _receiver);
    }

    /**
     * @notice Deactivates a receiver, preventing them from receiving future emissions.
     * @dev All deactivations should be accompanied by a reallocation of its existing weight via setReceiverWeights().
     *  If weights are not reallocated, emissions will accumulate as `unallocated`.
     * @param _id The ID of the receiver to deactivate
     */
    function deactivateReceiver(uint256 _id) external onlyOwner {
        ReceiverInfo memory receiver = idToReceiver[_id];
        require(receiver.receiver != address(0), "Receiver not found");
        require(receiver.active, "Receiver not active");
        _fetchEmissions(receiver.receiver);
        idToReceiver[_id].active = false;
        emit ReceiverDeactivated(_id);
    }
    
    /**
     * @notice Activates a receiver, allowing them to receive emissions.
     * @dev Receivers are activated when registered, so this is only needed for previously deactivated receivers.
     * @param _id The ID of the receiver to activate
     */
    function activateReceiver(uint256 _id) external onlyOwner {
        ReceiverInfo memory receiver = idToReceiver[_id];
        require(receiver.receiver != address(0), "Receiver not found");
        require(!receiver.active, "Receiver active");
        _fetchEmissions(receiver.receiver);
        idToReceiver[_id].active = true;
        emit ReceiverActivated(_id);
    }

    function transferFromAllocation(address _recipient, uint256 _amount) external returns (uint256) {
        if (_amount > 0) {
            allocated[msg.sender].amount -= _safeCastToUint200(_amount);
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
        
        // during bootstrap period, we have no emissions
        if (epoch <= BOOTSTRAP_EPOCHS) return 0;
        
        // bulk mints for the current epoch if not already done.
        _mintEmissions(epoch);
        
        Allocated memory _allocated = allocated[_receiver];
        if (_allocated.lastAllocEpoch >= epoch) return 0;
        ReceiverInfo memory receiver = idToReceiver[receiverToId[_receiver]];
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
        
        // don't need to mint if we're caught up already or during bootstrap
        if (epoch <= _lastMintEpoch) return;
        
        while (_lastMintEpoch < epoch) {
            uint256 mintable = _calcEmissionsForEpoch(++_lastMintEpoch);
            if (mintable > 0) govToken.mint(address(this), mintable);
            emissionsPerEpoch[_lastMintEpoch] = mintable;
        }
        lastMintEpoch = epoch;
    }


    function _calcEmissionsForEpoch(uint256 _epoch) internal returns (uint256) {
        uint256 _emissionsRate = emissionsRate;
        if (_epoch - lastEmissionsUpdate >= epochsPer) {
            uint256 len = emissionsSchedule.length;
            
            // check to make sure we have remaining updates left
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
            govToken.globalSupply() * 
            _emissionsRate * 
            epochLength /
            365 days /
            PRECISION
        );
    }

    function isRegisteredReceiver(address _receiver) public view returns (bool) {
        if (_receiver == address(0)) return false;
        uint256 id = receiverToId[_receiver];
        if (id == 0) return idToReceiver[0].receiver == _receiver;
        return id != 0;
    }

    /**
     * @notice Sets the emissions schedule and epochs per schedule item
     * @param _rates An array of inflation rates expressed as annual pct of total supply (100% = 1e18)
     * @param _epochsPer Number of epochs each schedule item lasts
     * @dev Rates must be in reverse order. Last item will be used first. No rate can be greater than the previous rate.
     * @dev All updates take effect in the epoch following the epoch in which the call is made.
     */
    function setEmissionsSchedule(uint256[] memory _rates, uint256 _epochsPer, uint256 _tailRate) external onlyOwner {
        require(_rates.length > 0 && _epochsPer > 0, "Must be >0");
        require(_rates[0] >= _tailRate, "Final rate less than tail rate");
        for (uint256 i = 0; i < _rates.length - 1; i++) {
            require(_rates[i] <= _rates[i + 1], "Rate greater than predecessor");
        }
        // before updating, and only if receiver(s) are registered, mint current epoch emissions at old rate
        if (nextReceiverId > 0) _mintEmissions(getEpoch());
        emissionsSchedule = _rates;
        epochsPer = _epochsPer;
        tailRate = _tailRate;
        emit EmissionsScheduleSet(_rates, _epochsPer, _tailRate);
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

    function _safeCastToUint200(uint256 _amount) internal pure returns (uint200) {
        require(_amount < type(uint200).max, "safecast-overflow");
        return uint200(_amount);
    }
}