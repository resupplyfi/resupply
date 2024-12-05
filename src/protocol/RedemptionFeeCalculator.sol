import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IRedemptionHandler } from "src/interfaces/IRedemptionHandler.sol";

//@notice used to track usage of redeeming a pair
contract RedemptionFeeCalculator {
    IRedemptionHandler public immutable redemptionHandler;
    mapping(address => RedemptionRateInfo) public pairRateInfo;
    uint256 public minuteDecayFactor = 1e18;

    uint256 public constant SECONDS_IN_ONE_MINUTE = 60;

    struct RedemptionRateInfo {
        uint64 timestamp;
        uint192 usage;
    }

    constructor(address _redemptionHandler){
        redemptionHandler = IRedemptionHandler(_redemptionHandler);
    }
    

    /// @notice Calculates the total redemption fee as a percentage of the redemption amount.
    /// TODO: add settable contract for upgradeable logic
    function previewRedemptionFee(address _pair, uint256 _amount) public view returns(uint256){
        (uint256 fee, ) = _getRedemptionFee(_pair, _amount);
        return fee;
    }

    function updateRedemptionFee(address _pair, uint256 _amount) external returns(uint256){
        require(msg.sender == address(redemptionHandler), "!redemptionHandler");
        (uint256 fee, RedemptionRateInfo memory rateInfo) = _getRedemptionFee(_pair, _amount);
        pairRateInfo[_pair] = rateInfo;
        return fee;
    }

    function _getRedemptionFee(address _pair, uint256 _amount) internal view returns(uint256, RedemptionRateInfo memory rateInfo){
        (, , , IResupplyPair.VaultAccount memory _totalBorrow) = IResupplyPair(_pair).previewAddInterest();

        if (_totalBorrow.amount == 0) return (redemptionHandler.baseRedemptionFee(), rateInfo);
        
        uint256 weightOfRedeem = _amount * 1e18 / _totalBorrow.amount;

        rateInfo = pairRateInfo[_pair];

        if(rateInfo.timestamp != 0){
            uint256 usageDecayRate = 1e17 / uint256(7 days); //10% per week
            uint256 timeElapsed = block.timestamp - rateInfo.timestamp;
            uint256 decay = timeElapsed * usageDecayRate;
            uint192 decayFactor = uint192(decay >= 1e18 ? 0 : 1e18 - decay);

            rateInfo.usage = rateInfo.usage * decayFactor / 1e18;
            rateInfo.timestamp = uint64(block.timestamp);
        }

        // 
        uint256 halfway = rateInfo.usage + (weightOfRedeem/2);
        
        rateInfo.usage += uint192(weightOfRedeem);
        rateInfo.timestamp = uint64(block.timestamp);

        uint256 maxusage = 1e17;
        uint256 discount = maxusage > halfway ? maxusage - halfway : 0;
        discount = (discount * 1e18 / maxusage); //discount is now a 1e18 precision % 
        discount = (2e15 * discount / 1e18);// reduce 2e18 by % above
        return (redemptionHandler.baseRedemptionFee() - discount, rateInfo);
    }

    function _xgetRedemptionFee(address _pair, uint256 _amount) internal view returns(uint256, RedemptionRateInfo memory rateInfo){
        (, , , IResupplyPair.VaultAccount memory _totalBorrow) = IResupplyPair(_pair).previewAddInterest();

        _updateBaseRateFromRedemption(_amount, _totalBorrow.amount);

        if (_totalBorrow.amount == 0) return (redemptionHandler.baseRedemptionFee(), rateInfo);
        
        uint256 elapsedTime = (block.timestamp - rateInfo.timestamp);
        uint256 decayFactor = PrismaMath._decPow(minuteDecayFactor, elapsedTime);

        return (baseRate * decayFactor) / DECIMAL_PRECISION;
    }


    function _updateBaseRateFromRedemption(
        uint256 _redemptionAmount,
        uint256 _totalDebtSupply
    ) internal returns (uint256) {
        uint256 decayedBaseRate = _calcDecayedBaseRate();

        uint256 redeemedDebtFraction = (_redemptionAmount) / _totalDebtSupply;

        uint256 newBaseRate = decayedBaseRate + (redeemedDebtFraction / BETA);
        newBaseRate = PrismaMath._min(newBaseRate, DECIMAL_PRECISION); // cap baseRate at a maximum of 100%

        // Update the baseRate state variable
        baseRate = newBaseRate;
        emit BaseRateUpdated(newBaseRate);

        _updateLastFeeOpTime();

        return newBaseRate;
    }

    function getRedemptionRate() public view returns (uint256) {
        return _calcRedemptionRate(baseRate);
    }

    function getRedemptionRateWithDecay() public view returns (uint256) {
        return _calcRedemptionRate(_calcDecayedBaseRate());
    }

    function _calcRedemptionRate(uint256 _baseRate) internal view returns (uint256) {
        return
            PrismaMath._min(
                redemptionFeeFloor + _baseRate,
                maxRedemptionFee // cap at a maximum of 100%
            );
    }

    function getRedemptionFeeWithDecay(uint256 _collateralDrawn) external view returns (uint256) {
        return _calcRedemptionFee(getRedemptionRateWithDecay(), _collateralDrawn);
    }

    function _calcRedemptionFee(uint256 _redemptionRate, uint256 _collateralDrawn) internal pure returns (uint256) {
        uint256 redemptionFee = (_redemptionRate * _collateralDrawn) / DECIMAL_PRECISION;
        require(redemptionFee < _collateralDrawn, "Fee exceeds returned collateral");
        return redemptionFee;
    }

    function _calcDecayedBaseRate() internal view returns (uint256) {
        uint256 elapsedTime = (block.timestamp - lastFeeOperationTime) / SECONDS_IN_ONE_MINUTE;
        uint256 decayAmount = (baseRate * minuteDecayFactor * elapsedTime) / DECIMAL_PRECISION;
        return decayAmount >= baseRate ? 0 : baseRate - decayAmount;
    }
}