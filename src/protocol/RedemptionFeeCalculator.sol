import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IRedemptionHandler } from "src/interfaces/IRedemptionHandler.sol";
import { ResupplyMath } from "src/dependencies/ResupplyMath.sol";
import { CoreOwnable } from "src/dependencies/CoreOwnable.sol";

//@notice used to track usage of redeeming a pair
contract RedemptionFeeCalculator is CoreOwnable {
    uint256 public constant DECIMAL_PRECISION = 1e18;
    IRedemptionHandler public immutable redemptionHandler;
    mapping(address => RedemptionRateInfo) public pairInfo;
    uint256 public constant SECONDS_IN_ONE_MINUTE = 60;

    struct RedemptionRateInfo {
        uint256 minuteDecayFactor;
        uint256 baseRate;
        uint64 lastFeeOperationTime;
        uint256 redemptionFeeFloor;
        uint256 maxRedemptionFee;
    }

    event BaseRateUpdated(uint256 newBaseRate);
    event LastFeeOpTimeUpdated(uint256 newLastFeeOpTime);

    constructor(address _core, address _redemptionHandler) CoreOwnable(_core) {
        redemptionHandler = IRedemptionHandler(_redemptionHandler);
        // Create default settings
        pairInfo[address(0)] = RedemptionRateInfo({
            minuteDecayFactor: 999037758833783000, // (half-life of 12 hours)
            baseRate: 0,
            lastFeeOperationTime: 0,
            redemptionFeeFloor: DECIMAL_PRECISION / 1000 * 5,   //  (0.5%)
            maxRedemptionFee: DECIMAL_PRECISION                 //  (100%)
        });
    }

    function updateRedemptionFee(address _pair, uint256 _debtRepaid) external returns(uint256){
        require(msg.sender == address(redemptionHandler), "!redemptionHandler");
        uint256 fee = _getRedemptionFee(_pair, _debtRepaid);
        return fee;
    }

    function _getRedemptionFee(address _pair, uint256 _amount) internal returns(uint256){
        (, , , IResupplyPair.VaultAccount memory _totalBorrow) = IResupplyPair(_pair).previewAddInterest();
        RedemptionRateInfo memory _rateInfo = pairInfo[_pair];
        if(_rateInfo.minuteDecayFactor == 0) _rateInfo = pairInfo[address(0)]; // default settings stored at 0x0 address
            
        _updateBaseRateFromRedemption(_pair, _rateInfo, _amount, _totalBorrow.amount);

        if (_totalBorrow.amount == 0) return redemptionHandler.baseRedemptionFee();

        return _calcRedemptionFee(_pair, getRedemptionRate(_pair), _amount);
    }

    function _calcDecayedBaseRate(address _pair) internal view returns (uint256) {
        uint256 minutesPassed = (block.timestamp - pairInfo[_pair].lastFeeOperationTime) / SECONDS_IN_ONE_MINUTE;
        uint256 decayFactor = ResupplyMath._decPow(pairInfo[_pair].minuteDecayFactor, minutesPassed);

        return (pairInfo[_pair].baseRate * decayFactor) / DECIMAL_PRECISION;
    }

    function _updateBaseRateFromRedemption(
        address _pair,
        RedemptionRateInfo memory _rateInfo,
        uint256 _redemptionValue,
        uint256 _totalDebtSupply
    ) internal returns (uint256) {
        uint256 decayedBaseRate = _calcDecayedBaseRate(_pair);

        uint256 redeemedDebtFraction = (_redemptionValue) / _totalDebtSupply;

        uint256 newBaseRate = decayedBaseRate + (redeemedDebtFraction / 2);
        newBaseRate = ResupplyMath._min(newBaseRate, DECIMAL_PRECISION); // cap baseRate at a maximum of 100%

        // Update the baseRate state variable
        _rateInfo.baseRate = newBaseRate;
        emit BaseRateUpdated(newBaseRate);

        _updateLastFeeOpTime(_pair, _rateInfo.lastFeeOperationTime);

        return newBaseRate;
    }

    function getRedemptionRate(address _pair) public view returns (uint256) {
        return _calcRedemptionRate(_pair, pairInfo[_pair].baseRate);
    }

    function getRedemptionRateWithDecay(address _pair) public view returns (uint256) {
        return _calcRedemptionRate(_pair, _calcDecayedBaseRate(_pair));
    }

    function _calcRedemptionRate(address _pair, uint256 _baseRate) internal view returns (uint256) {
        return
            ResupplyMath._min(
                pairInfo[_pair].redemptionFeeFloor + _baseRate,
                pairInfo[_pair].maxRedemptionFee // cap at a maximum of 100%
            );
    }

    function getRedemptionFeeWithDecay(address _pair, uint256 _debtRepaid) external view returns (uint256) {
        return _calcRedemptionFee(_pair, getRedemptionRateWithDecay(_pair), _debtRepaid);
    }

    function _calcRedemptionFee(address _pair, uint256 _redemptionRate, uint256 _debtRepaid) internal pure returns (uint256) {
        uint256 redemptionFee = (_redemptionRate * _debtRepaid) / DECIMAL_PRECISION;
        require(redemptionFee < _debtRepaid, "Fee exceeds total debt repaid");
        return redemptionFee;
    }

    function _updateLastFeeOpTime(address _pair, uint256 _lastFeeOperationTime) internal {
        uint256 timePassed = block.timestamp - _lastFeeOperationTime;

        if (timePassed >= SECONDS_IN_ONE_MINUTE) {  
            pairInfo[_pair].lastFeeOperationTime = uint64(block.timestamp);
            emit LastFeeOpTimeUpdated(block.timestamp);
        }
    }

    function setDefaultSettings(
        uint256 _minuteDecayFactor, 
        uint256 _redemptionFeeFloor, 
        uint256 _maxRedemptionFee
    ) external onlyOwner {
        pairInfo[address(0)] = RedemptionRateInfo({
            minuteDecayFactor: _minuteDecayFactor,
            baseRate: 0,
            lastFeeOperationTime: 0,
            redemptionFeeFloor: _redemptionFeeFloor,
            maxRedemptionFee: _maxRedemptionFee
        });
    }
}