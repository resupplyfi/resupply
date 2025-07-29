// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IERC4626 } from "../interfaces/IERC4626.sol";
import { IReusdOracle } from "../interfaces/IReusdOracle.sol";
import { IResupplyRegistry } from "../interfaces/IResupplyRegistry.sol";
import { IResupplyPair } from "../interfaces/IResupplyPair.sol";
import { CoreOwnable } from "../dependencies/CoreOwnable.sol";

/// @title Keep track of reusd discount with a time weighted value
contract PriceWatcher is CoreOwnable{

    uint256 public constant UPDATE_INTERVAL = 6 hours;
    address public immutable registry;
    address public oracle;

    struct PriceData{
        uint64 timestamp;
        uint64 weight;
        uint128 totalWeight;
    }

    PriceData[] public priceData;
    mapping(uint256 => uint256) public timeMap;

    event NewPriceData(uint256 indexed index, uint64 timestamp, uint64 weight, uint128 weightedValue);
    event OracleSet(address indexed oracle);

    /// @notice The ```constructor``` function
    /// @param _registry registry address
    constructor(
        address _registry
    ) CoreOwnable( IResupplyRegistry(_registry).owner() ) {
        registry = _registry;
        oracle = IResupplyRegistry(_registry).getAddress("REUSD_ORACLE");
        require(oracle != address(0), "invalid address");
        //start with at least 2 nodes of information
        _addUpdate(0, 0, 0);
        updatePriceData();
    }

    /// @notice The ```setOracle``` function pulls oracle address from registry and sets
    function setOracle() external onlyOwner {
        address _oracle = IResupplyRegistry(registry).getAddress("REUSD_ORACLE");
        require(_oracle != address(0), "invalid address");
        require(IReusdOracle(_oracle).price() > 0, "price invalid");
        if (_oracle != oracle) {
            oracle = _oracle;
            emit OracleSet(_oracle);
        }
    }

    function priceDataLength() external view returns(uint256){
        return priceData.length;
    }

    function priceDataAtIndex(uint256 i) external view returns(PriceData memory _pd){
        _pd = priceData[i];
    }

    function latestPriceData() public view returns(PriceData memory _pd){
        _pd = priceData[priceData.length-1];
    }

    //refer to price oracle and update price weighting
    function updatePriceData() public{
        uint64 timestamp = uint64(block.timestamp);
        
        //get most recent priceData node to see if enough time has elapsed
        PriceData memory latestPriceData = latestPriceData();
        uint64 timedifference = timestamp - latestPriceData.timestamp;
        if(timedifference < UPDATE_INTERVAL) return;

        _addUpdate(
            timestamp,
            getCurrentWeight(), 
            (latestPriceData.weight * timedifference) + latestPriceData.totalWeight
        );
    }

    function _getTimestampFloor(uint256 _timestamp)  internal view returns(uint256){
        return (_timestamp/UPDATE_INTERVAL) * UPDATE_INTERVAL;
    }

    function _addUpdate(uint64 _timestamp, uint64 _weight, uint128 _totalweight) internal{
        uint256 newIndex = priceData.length;
        priceData.push(PriceData({
            timestamp: _timestamp,
            weight: _weight,
            totalWeight: _totalweight
        }));

        timeMap[ _getTimestampFloor(_timestamp) ] = newIndex;

        emit NewPriceData(newIndex, _timestamp, _weight, _totalweight);
    }

    function findPairPriceWeight(address _pair) external view returns(uint256){
        uint64 timestamp = uint64(block.timestamp);
        
        //get pair's most recent timestamp on interest update
        (uint64 lastPairUpdate, ,) = IResupplyPair(_pair).currentRateInfo();

        //get floored timestamp
        uint256 ftime = _getTimestampFloor(lastPairUpdate);
        uint256 currentIndex = timeMap[ftime];

        //if no record for given floored time check previous timespan
        //this should really only need to check once but
        //we loop just in case price watcher was not updated for a very long time
        //but impossible to loop forever
        while(currentIndex == 0){
            ftime -= UPDATE_INTERVAL;
            currentIndex = timeMap[ftime];
        }
        
        //get the current price data using the found index
        PriceData memory current = priceData[currentIndex];

        //however we need to check timestamps again since the price node could have been written after addInterest
        if(current.timestamp > lastPairUpdate){
            //if current is greater, then its guaranteed that the correct node is currentIndex - 1
            currentIndex--;
            current = priceData[currentIndex];
        }

        //get latest index and price data
        uint256 latestIndex = priceData.length - 1;
        //quick check if current is equal to latest, if so just return latest's weight
        if(currentIndex == latestIndex) return current.weight;

        PriceData memory latest = priceData[latestIndex];
        
        //extrapolate a starting point thats between currentIndex and currentIndex+1
        //at the timestamp of lastPairUpdate (which will always be equal to or greater than current.timestamp)
        uint64 dt = lastPairUpdate - current.timestamp;
        current.timestamp = lastPairUpdate;
        current.totalWeight += current.weight * dt;
        //extrapolate a new data point that uses latest's weight and the time difference between
        //latest and block.timestamp 
        dt = timestamp - latest.timestamp;
        latest.timestamp = timestamp;
        latest.totalWeight += latest.weight * dt;

        //get difference of total weight between these two points
        uint256 dw = latest.totalWeight - current.totalWeight;
        dt = latest.timestamp - current.timestamp;

        //divide by time between these two points to get average weight during the timespan
        return dw / dt;
    }

    function getCurrentWeight() public view returns (uint64) {
        uint256 price = IReusdOracle(oracle).priceAsCrvusd();
        uint256 weight = price > 1e18 ? 0 : 1e18 - price;
        //our oracle has a floor that matches redemption fee
        //e.g. it returns a minimum price of 0.9900 when there is a 1% redemption fee
        //at this point a price of 0.99000 has a weight of 0.010000 or 1e16
        //reduce precision to 1e6
        return uint64(weight / 1e10);
    }

    /// @notice Helper function to check if price watcher state data can be updated
    function canUpdatePriceData() external view returns(bool){
        return block.timestamp - latestPriceData().timestamp >= UPDATE_INTERVAL;
    }
}