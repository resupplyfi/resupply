// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import { Protocol } from "src/Constants.sol";
import { console } from "lib/forge-std/src/console.sol";
import { Setup } from "test/integration/Setup.sol";
import { BorrowLimitController } from "src/dao/operators/BorrowLimitController.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IAuthHook } from 'src/interfaces/IAuthHook.sol';

contract BorrowLimitControllerTest is Setup {
    
    BorrowLimitController public borrowController;

    function setUp() public override {
        super.setUp();
        
        //deploy controller
        borrowController = new BorrowLimitController(
            address(core)
        );

      
        vm.startPrank(address(core));
        core.setOperatorPermissions(
            address(borrowController),
            address(0),
            IResupplyPair.setBorrowLimit.selector,
            true,
            IAuthHook(address(0))
        );
        vm.stopPrank();
    }

    function printRampInfo(address _pair) private{
        // BorrowLimitController.PairBorrowLimit memory info = borrowController.pairLimits(_pair);
        (uint256 targetBorrowLimit, uint256 prevBorrowLimit, uint64 start, uint64 end) = borrowController.pairLimits(_pair);
    
        console.log("---------------------------");
        console.log("pair: ", _pair);
        console.log("targetBorrowLimit: ", targetBorrowLimit);
        console.log("prevBorrowLimit: ", prevBorrowLimit);
        console.log("start: ", start);
        console.log("end: ", end);
        console.log("finished: ", start==0);
        console.log("actual borrow on pair: ", IResupplyPair(_pair).borrowLimit());

    }

    function test_borrowRamp() public {

        IResupplyPair pair = IResupplyPair(Protocol.PAIR_CURVELEND_SFRXUSD_CRVUSD);
        uint256 startBorrow = pair.borrowLimit();
        console.log("start borrow limit: ", startBorrow);

        console.log("before set ramp");
        printRampInfo(address(pair));

        uint256 finalTarget = 100_000_000e18;
        uint256 startTime = vm.getBlockTimestamp();
        uint256 finalTime = startTime + 10 days;
        vm.startPrank(address(core));
        borrowController.setPairBorrowLimitRamp(address(pair), finalTarget, finalTime);
        vm.stopPrank();

        console.log("after set ramp");
        printRampInfo(address(pair));

        for(uint256 i; i < 12; i++){
            console.log("\n\nskip forward in time and call update..");
            skip(1 days);
            (, ,uint64 start ,) = borrowController.pairLimits(address(pair));
            if(start==0) vm.expectRevert();
            borrowController.updatePairBorrowLimit(address(pair));
            printRampInfo(address(pair));
        }
    }

}