// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol } from "src/Constants.sol";
import { console } from "lib/forge-std/src/console.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IRedemptionHandler } from "src/interfaces/IRedemptionHandler.sol";
import { BaseProposal } from "script/proposals/BaseProposal.sol";

interface IPermastakerOperator {
    function safeExecute(address target, bytes calldata data) external;
    function createNewProposal(IVoter.Action[] calldata actions, string calldata description) external;
}

contract SetRedemptionHandler is BaseProposal {
    uint256 public constant WEIGHT_LIMIT = 1e17;
    function run() public isBatch(deployer) {
        deployMode = DeployMode.FORK;

        IVoter.Action[] memory data = buildProposalCalldata();
        proposeVote(data, "Upgrade redemption handler and set overweight param to 10%");
        
        if (deployMode == DeployMode.PRODUCTION){
            executeBatch(true);
        } 
    }

    function buildProposalCalldata() public override returns (IVoter.Action[] memory actions) {
        actions = new IVoter.Action[](2);
        // 1: Registry.setAddress("REDEMPTION_HANDLER", REDEMPTION_HANDLER)
        actions[0] = IVoter.Action({
            target: address(registry),
            data: abi.encodeWithSelector(
                IResupplyRegistry.setRedemptionHandler.selector,
                Protocol.REDEMPTION_HANDLER
            )
        });
        // 2: RedemptionHandler.setWeightLimit(1e17)
        actions[1] = IVoter.Action({
            target: Protocol.REDEMPTION_HANDLER,
            data: abi.encodeWithSelector(
                IRedemptionHandler.setWeightLimit.selector,
                WEIGHT_LIMIT
            )
        });
        
        console.log("Number of actions:", actions.length);
        console.log("Redemption handler:", Protocol.REDEMPTION_HANDLER);
    }
}
