// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IERC4626 } from "../interfaces/IERC4626.sol";
import { IReusdOracle } from "../interfaces/IReusdOracle.sol";
import { IResupplyRegistry } from "../interfaces/IResupplyRegistry.sol";
import { IResupplyPair } from "../interfaces/IResupplyPair.sol";

/// @title Keep track of reusd discount with a time weighted value
contract PriceWatcher {

    address public immutable oracle;

    struct PriceData{
        uint64 timestamp;
        uint64 weight;
        uint128 totalWeight;
    }

    PriceData[] public priceData;
    mapping(address => uint256) priceIndex;

    uint256 public immutable requiredWeightDifference; //todo keep immutable? or setter?

    event NewPriceData(uint64 timestamp, uint64 weight, uint128 weightedValue);

    /// @notice The ```constructor``` function
    /// @param _registry registry address
    /// @param _reqWeight amount of weight change needed to register a price change
    constructor(
        address _registry,
        uint256 _reqWeight
    ) {
        oracle = IResupplyRegistry(_registry).getAddress("REUSD_ORACLE");
        requiredWeightDifference = _reqWeight;

        //start with at least 2 nodes of information
        _addUpdate(uint64(block.timestamp - 1 hours), 0, 0);
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

    function updatePriceData() public{
        uint256 timestamp = block.timestamp;
        PriceData memory recent = priceData[priceData.length-1];
        uint256 timedifference = timestamp - recent.timestamp;

        //only update periodically
        if(timedifference < 1 hours) return;

        //get weight
        uint256 price = IReusdOracle(oracle).price();
        uint256 weight = price > 1e18 ? 0 : 1e18 - price;
        //our oracle has a floor that matches redemption fee, thus 0.9900
        //at this point a price of 0.99000 has a weight of 0.010000 or 1e16
        //reduce precision to 1e6
        weight /= 1e10;
        //max weight is 1,000,000 or 1e6

        uint256 weightdiff = weight > recent.weight ? weight - recent.weight : recent.weight - weight;
        //only write to state if there is a significant enough change in weight
        if(weightdiff < requiredWeightDifference) return;

        //add weighted time from previous checkpoint to total
        uint256 newTotalWeight = (recent.weight * timedifference) + recent.totalWeight;
        _addUpdate(uint64(timestamp), uint64(weight), uint128(newTotalWeight));
    }

    function _addUpdate(uint64 _timestamp, uint64 _weight, uint128 _totalweight) internal{
        priceData.push(PriceData({
            timestamp: _timestamp,
            weight: _weight,
            totalWeight: _totalweight
        }));

        emit NewPriceData(_timestamp, _weight, _totalweight);
    }

    //given a pair's last update of interest rates, check to see what priceData node
    //is the latest node in which its timestamp is less than the timestamp on the pair's rate info
    //by slowly moving up a pair's index we create a better start position for when the pair does
    //another interest rate update
    function updatePairPriceHistory(address _pair) external{
        //this function is isolated to the given pair so no real need to check if
        //the given pair address is a resupply pair or not

        uint256 latestIndex = priceData.length - 1;
        uint256 currentIndex = priceIndex[_pair];
        
        if(currentIndex == latestIndex){
            //no update needed
            return;
        }

        //a new pair being added will have a long list to check against so just skip
        //to the latest index on the first calll
        if(currentIndex == 0){
            priceIndex[_pair] = latestIndex;
            return;
        }

        //get pair's most recent timestamp on interest update
        (uint64 lastPairUpdate, ,) = IResupplyPair(_pair).currentRateInfo();

        uint256 nextIndex = currentIndex;
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

            //after increasing currenIndex, check if its the last break if needed
            if(nextIndex == latestIndex){
                break;
            }
        }
        if(nextIndex != currentIndex){
            //update the pair's current index
            priceIndex[_pair] = currentIndex;
        }
    }
}
