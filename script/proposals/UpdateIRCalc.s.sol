// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { BaseProposal } from "script/proposals/BaseProposal.sol";

contract UpdateIRCalc is BaseAction, BaseProposal {
    address public constant NEW_RATE_CALCULATOR = 0x42F9c30Fa365508B6Ce1c62B0269d3678aCcdffA;

    function run() public isBatch(deployer) {
        IVoter.Action[] memory data = buildProposalCalldata();
        proposeVote(data, "Update Interest Rate Calculator");

        deployMode = DeployMode.FORK;
        if (deployMode == DeployMode.PRODUCTION) {
            executeBatch(true);
        }
    }

    function buildProposalCalldata() public override returns (IVoter.Action[] memory actions) {
        address rateCalculator = NEW_RATE_CALCULATOR;
        require(rateCalculator != address(0), "rate calculator not set");
        require(rateCalculator.code.length > 0, "rate calculator not deployed");

        actions = new IVoter.Action[](numPairs);
        for (uint256 i = 0; i < pairs.length; i++) {
            actions[i] = IVoter.Action({
                target: pairs[i],
                data: abi.encodeWithSelector(
                    IResupplyPair.setRateCalculator.selector,
                    rateCalculator,
                    false // avoid invoking the buggy old calculator during the switch
                )
            });
        }
    }
}
