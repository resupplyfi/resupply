// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol } from "src/Constants.sol";
import { console } from "lib/forge-std/src/console.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { IBorrowLimitController } from "src/interfaces/IBorrowLimitController.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { BaseProposal } from "script/proposals/BaseProposal.sol";

contract AdjustBorrowLimits is BaseProposal {

    struct PairData {
        address pair;
        uint256 targetLimit;
        string pairName;
    }

    uint256 public rampEndTime = block.timestamp + 20 days;

    function run() public isBatch(deployer) {
        deployMode = DeployMode.FORK;

        IVoter.Action[] memory data = buildProposalCalldata();
        proposeVote(data, "Adjust pair borrow limits");
        
        if (deployMode == DeployMode.PRODUCTION){
            executeBatch(true);
        } 
    }

    function buildProposalCalldata() public override returns (IVoter.Action[] memory actions) {
        PairData[] memory pairData = getPairData();
        actions = new IVoter.Action[](pairData.length);
        for (uint256 i = 0; i < pairData.length; i++) {
            PairData memory pair = pairData[i];
            IResupplyPair pairContract = IResupplyPair(pair.pair);
            uint256 currentBorrowLimit = pairContract.borrowLimit();
            // if increasing, use the borrow limit controller to ramp
            if (currentBorrowLimit < pair.targetLimit) {
                actions[i] = IVoter.Action({
                    target: Protocol.BORROW_LIMIT_CONTROLLER,
                    data: abi.encodeWithSelector(
                        IBorrowLimitController.setPairBorrowLimitRamp.selector,
                        pair.pair,
                        pair.targetLimit,
                        rampEndTime
                    )
                });
            }
            // if decreasing, set the borrow limit directly
            else {
                actions[i] = IVoter.Action({
                    target: pair.pair,
                    data: abi.encodeWithSelector(
                        IResupplyPair.setBorrowLimit.selector,
                        pair.targetLimit
                    )
                });
            }
            
        }
    }

    function getPairData() public view returns (PairData[] memory) {
        PairData[] memory pairData = new PairData[](4);
        pairData[0] = PairData({
            pair: 0x3b037329Ff77B5863e6a3c844AD2a7506ABe5706,
            targetLimit: 0,
            pairName: "CurveLend: crvUSD/USDe"
        });
        pairData[1] = PairData({
            pair: 0x57E69699381a651Fb0BBDBB31888F5D655Bf3f06,
            targetLimit: 0,
            pairName: "CurveLend: crvUSD/sUSDS"
        });
        pairData[2] = PairData({
            pair: 0xF4A6113FbD71Ac1825751A6fe844A156f60C83EF,
            targetLimit: 0,
            pairName: "CurveLend: crvUSD/tBTC"
        });
        pairData[3] = PairData({
            pair: 0xD42535Cda82a4569BA7209857446222ABd14A82c,
            targetLimit: 25_000_000e18,
            pairName: "CurveLend: crvUSD/fxSAVE"
        });
        return pairData;
    }
}