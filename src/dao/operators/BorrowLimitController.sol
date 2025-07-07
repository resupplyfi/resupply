// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ICore } from "src/interfaces/ICore.sol";
import { CoreOwnable } from "src/dependencies/CoreOwnable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";


//A core operator that has access to change pair's borrow limits over a period of time
contract BorrowLimitController is CoreOwnable {
    using SafeERC20 for IERC20;


    struct PairBorrowLimit{
        uint256 borrowLimit;
        uint256 prevBorrowLimit;
        uint64 startTime; 
        uint64 endTime;
        bool finished;
    }

    mapping(address => PairBorrowLimit) public pairLimits;

    event NewBorrowRamp(address indexed pair, uint256 fromBorrow, uint256 toBorrow, uint256 endTime);
    event NewBorrowLimit(address indexed pair, uint256 borrowLimit);

    constructor(address _core) CoreOwnable(_core) {

    }


    function setPairBorrowLimitRamp(address _pair, uint256 _newBorrowLimit, uint256 _endTime) external onlyOwner {
        PairBorrowLimit memory limitInfo;

        limitInfo.borrowLimit = _newBorrowLimit;
        limitInfo.prevBorrowLimit = IResupplyPair(_pair).borrowLimit();
        limitInfo.startTime = uint64(block.timestamp);
        limitInfo.endTime = uint64(_endTime);

        require(limitInfo.borrowLimit > limitInfo.prevBorrowLimit, "can only ramp up");
        require(limitInfo.endTime >= limitInfo.startTime + 7 days, "rate of change too high");

        pairLimits[_pair] = limitInfo;

        emit NewBorrowRamp(_pair, limitInfo.prevBorrowLimit, limitInfo.borrowLimit, _endTime);
    }

    function updatePairBorrowLimit(address _pair) external{
        PairBorrowLimit memory limitInfo = pairLimits[_pair];

        //check if pair current borrow is between prev and end (and not paused etc)
        uint256 currentBorrowLimit = IResupplyPair(_pair).borrowLimit();
        require(currentBorrowLimit >= limitInfo.prevBorrowLimit && currentBorrowLimit <= limitInfo.borrowLimit, "current borrow limit outside of range");
        //check if ramp is already finished
        require(!limitInfo.finished, "already finished");

        //get how far along we are in the ramp
        uint256 dt =  (block.timestamp - limitInfo.startTime) * 10_000 / (limitInfo.endTime - limitInfo.startTime);
        if(dt > 10_000){
            //set to max dt and flag as finished
            dt = 10_000;
            limitInfo.finished = true;
            pairLimits[_pair] = limitInfo;
        }

        uint256 borrowDelta = limitInfo.borrowLimit - limitInfo.prevBorrowLimit;
        uint256 newBorrow = ((borrowDelta * dt) / 10_000) + limitInfo.prevBorrowLimit;
        
        IResupplyPair(_pair).setBorrowLimit(newBorrow);
    }

}
