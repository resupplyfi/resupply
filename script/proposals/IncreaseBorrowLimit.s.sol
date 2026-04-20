// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol } from "src/Constants.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { IRedemptionHandler } from "src/interfaces/IRedemptionHandler.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { BaseProposal } from "script/proposals/BaseProposal.sol";

contract IncreaseBorrowLimit is BaseProposal {
    address public constant PAIR = 0x2fdD3c0a682e5774205F0F6D3eD3c9D1b9Cb9413;
    uint256 public constant RAMP_DURATION = 17 days;

    function run() public isBatch(deployer) {
        deployMode = DeployMode.PRODUCTION;

        IVoter.Action[] memory data = buildProposalCalldata();
        proposeVote(data, "Ramp crvUSD/sreUSD borrow limit 2x and edit operator permission target");

        if (deployMode == DeployMode.PRODUCTION) {
            executeBatch(true);
        }
    }

    function buildProposalCalldata() public override returns (IVoter.Action[] memory actions) {
        uint256 currentBorrowLimit = IResupplyPair(PAIR).borrowLimit();
        require(currentBorrowLimit > 0, "pair borrow limit is zero");

        actions = new IVoter.Action[](3);
        // 2x borrow limit over 15 days from proposal creation
        actions[0] = IVoter.Action({
            target: Protocol.BORROW_LIMIT_CONTROLLER,
            data: getRampBorrowLimitCallData(
                PAIR,
                currentBorrowLimit * 2,
                block.timestamp + RAMP_DURATION
            )
        });
        // Remove old permission
        actions[1] = setOperatorPermission(
            Protocol.OPERATOR_GUARDIAN_PROXY,
            Protocol.REDEMPTION_HANDLER,
            IRedemptionHandler.updateGuardSettings.selector,
            false
        );
        // Add wildcarded permission
        actions[2] = setOperatorPermission(
            Protocol.OPERATOR_GUARDIAN_PROXY,
            address(0),
            IRedemptionHandler.updateGuardSettings.selector,
            true
        );
    }
}
