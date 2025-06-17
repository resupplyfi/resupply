// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IERC4626 } from "../interfaces/IERC4626.sol";
import { IReusdOracle } from "../interfaces/IReusdOracle.sol";
import { IResupplyRegistry } from "../interfaces/IResupplyRegistry.sol";
import { IResupplyPair } from "../interfaces/IResupplyPair.sol";

/// @title Keep track of reusd discount with a time weighted value
contract PriceWatcher {

    address public immutable oracle;
    uint256 public constant INTERIM_UPDATE_INTERVAL = 1 hours;
    uint256 public constant UPDATE_INTERVAL = 12 hours;

    struct PriceData{
        uint64 timestamp;
        uint64 weight;
        uint128 totalWeight;
    }

    PriceData[] public priceData;
    mapping(address => uint256) public priceIndex;

    PriceData public interimData;

    event NewPriceData(uint64 timestamp, uint64 weight, uint128 weightedValue);

    /// @notice The ```constructor``` function
    /// @param _registry registry address
    constructor(
        address _registry
    ) {
        oracle = IResupplyRegistry(_registry).getAddress("REUSD_ORACLE");
        // requiredWeightDifference = _reqWeight;

        //start with at least 2 nodes of information
        _addUpdate(0, getCurrentWeight(), 0);
        updatePriceData();
    }

    function priceDataLength() external view returns(uint256){
        return priceData.length;
    }

    function priceDataAtIndex(uint256 i) external view returns(PriceData memory _pd){
        _pd = priceData[i];
    }

    function latestPriceData() external view returns(PriceData memory _pd){
        _pd = priceData[priceData.length-1];
    }

    //refer to price oracle and update price weighting
    function updatePriceData() public{

        //in order to reduce number of priceData nodes written to state (and thus number of nodes needed to be proceessed),
        //we will first watch price over a short period and record it as an average in interimData
        //next we will check if a longer period of time has elapsed and if so write the interimData as a new priceData node

        uint256 timestamp = block.timestamp;
        PriceData memory interim = interimData;
        uint256 timedifference = timestamp - interim.timestamp;

        //update interim periodically but at a faster rate than priceData nodes
        if(timedifference < INTERIM_UPDATE_INTERVAL) return;
        
        uint64 weight = getCurrentWeight();
        
        //use previous interim weight to add to a total weight since last checkpoint
        interim.totalWeight = uint128(interim.totalWeight + (interim.weight * timedifference));
        //then update new interim weight and timestamp
        interim.weight = weight;
        interim.timestamp = uint64(timestamp);

        
        //get most recent priceData node to see if enough time has elapsed
        PriceData memory recent = priceData[priceData.length-1];
        timedifference = timestamp - recent.timestamp;
        if(timedifference < UPDATE_INTERVAL){
            //if not enough time, still need to save interim
            //write interim data and return
            interimData = interim;
            return;
        }

        //get avg weight throughout the interim
        weight = uint64(interim.totalWeight / timedifference);

        //reset interim total weight and write to state
        //interim weight and timestamp will be equal to the new priceData node
        interim.totalWeight = 0;
        interimData = interim;

        //add weighted time from previous checkpoint to total
        uint256 newTotalWeight = (recent.weight * timedifference) + recent.totalWeight;
        //add new price data node
        _addUpdate(uint64(timestamp), weight, uint128(newTotalWeight));
    }

    function _addUpdate(uint64 _timestamp, uint64 _weight, uint128 _totalweight) internal{
        priceData.push(PriceData({
            timestamp: _timestamp,
            weight: _weight,
            totalWeight: _totalweight
        }));

        emit NewPriceData(_timestamp, _weight, _totalweight);
    }

    function getCurrentWeight() public view returns (uint64) {
        uint256 price = IReusdOracle(oracle).price();
        uint256 weight = price > 1e18 ? 0 : 1e18 - price;
        //our oracle has a floor that matches redemption fee
        //e.g. it returns a minimum price of 0.9900 when there is a 1% redemption fee
        //at this point a price of 0.99000 has a weight of 0.010000 or 1e16
        //reduce precision to 1e6
        return uint64(weight / 1e10);
    }

    //bulk update for pairs
    function updatePairsPriceHistory(address[] memory pairs) external{
        uint256 length = pairs.length;
        //for each pair, update the price history
        for(uint256 i = 0; i < length; i++){
            updatePairPriceHistory(pairs[i]);
        }
    }

    //given a pair's last update of interest rates, check to see what priceData node
    //is the latest node in which its timestamp is less than the timestamp on the pair's rate info
    //by slowly moving up a pair's index we create a better start position for when the pair does
    //another interest rate update
    function updatePairPriceHistory(address _pair) public{
        //this function is isolated to the given pair so no real need to check if
        //the given pair address is a resupply pair or not

        uint256 priceDataIndex = priceData.length - 1;
        uint256 pairIndex = priceIndex[_pair];
        
        if(pairIndex == priceDataIndex){
            //no update needed
            return;
        }

        //a new pair being added will have a long list to check against so just skip
        //to the latest index on the first calll
        if(pairIndex == 0){
            priceIndex[_pair] = priceDataIndex;
            return;
        }

        //get pair's most recent timestamp on interest update
        (uint64 lastPairUpdate, ,) = IResupplyPair(_pair).currentRateInfo();

        //we assume latest index has a high probability to match so check it first
        PriceData memory latestNode = priceData[priceDataIndex];
        if(lastPairUpdate >= latestNode.timestamp){
            priceIndex[_pair] = priceDataIndex; // NOTE: why not force an update to price data? could be stale?
            return;
        }

        //if timestamp doesnt match latest, we are forced to search for where the index should be..
        uint256 nextIndex = pairIndex;
        //step through pairData array to find the most up to data node
        //limit max steps as to not overly inflate gas costs
        for(uint256 i = 0; i < 5;){

            //get next data set
            PriceData memory next = priceData[nextIndex+1];

            //if the next node has a higher timestamp, break without increase nextIndex
            if(next.timestamp > lastPairUpdate){
                break;
            }

            //increase indicies
            unchecked{
                ++i;
                ++nextIndex;
            }

            //after increasing nextIndex, check if its the last and break if needed
            if(nextIndex == priceDataIndex){
                break;
            }
        }
        if(nextIndex != pairIndex){
            //update the pair's current index
            priceIndex[_pair] = nextIndex;
        }
    }

    function updatePairPriceHistoryAtIndex(address _pair, uint256 _index) external{
        uint256 currentIndex = priceIndex[_pair];

        //if given 0 then set index as the most recent
        if(_index == 0){
            _index = priceData.length - 1;
        }

        //only try updating if index is greater than current
        if(_index > currentIndex){
            //get pair's most recent timestamp on interest update
            (uint64 lastPairUpdate, ,) = IResupplyPair(_pair).currentRateInfo();

            PriceData memory pd = priceData[_index];
            //if last update is greater or equal then move index up
            if(lastPairUpdate >= pd.timestamp){
                //write to state
                priceIndex[_pair] = _index;
            }
        }
    }

    function findPairPriceWeight(address _pair) external view returns(uint256){
        
        uint256 currentIndex = priceIndex[_pair];
        uint256 latestIndex = priceData.length - 1;

        if(currentIndex == latestIndex){
            //if pair is at latest then there has been no change in weight
            //calculation is a simple return of latest's weight
            return priceData[latestIndex].weight;
        }

        //get pair's most recent timestamp on interest update
        (uint64 lastPairUpdate, ,) = IResupplyPair(_pair).currentRateInfo();

        //we assume latest index has a high probability to match so check it first
        PriceData memory latestNode = priceData[latestIndex];
        if(lastPairUpdate >= latestNode.timestamp){
            return priceData[latestIndex].weight;
        }

        //loop till we find our starting point
        //this can be exhaustive on gas so ensuring starting index is updated frequently is a must
        //however global system settings should limit the worst case situation
        for(;;){

            //get next data set
            PriceData memory next = priceData[currentIndex+1];

            //if the next node has a higher timestamp, break without increase nextIndex
            if(next.timestamp > lastPairUpdate){
                break;
            }

            //increase index
            unchecked{
                ++currentIndex;
            }

            //check if current is last and return if needed
            if(currentIndex == latestIndex){
                //if pair is at latest then there has been no change in weight
                //calculation is a simple return of latest's weight
                return priceData[latestIndex].weight;
            }
        }

        //get current and extrapolate a starting point thats inbetween currentIndex and currentIndex+1
        //at the timestamp of lastPairUpdate (which will always be equal to or greater than current.timestamp)
        PriceData memory current = priceData[currentIndex];
        uint64 dt = lastPairUpdate - current.timestamp;
        current.timestamp = current.timestamp + dt;
        current.totalWeight = current.totalWeight + (current.weight * dt);

        //get latest data and extrapolate a new data point that uses latest's weight and the time difference between
        //latest and block.timestamp 
        PriceData memory latest = priceData[latestIndex];
        dt = uint64(block.timestamp) - latest.timestamp;
        latest.timestamp = latest.timestamp + dt;
        latest.totalWeight = latest.totalWeight + (latest.weight * dt);

        //get difference of total weight between these two points
        uint256 dw = latest.totalWeight - current.totalWeight;
        dt = latest.timestamp - current.timestamp;

        //divide by time between these two points to get average weight during the timespan
        return dw / dt;
    }
}
