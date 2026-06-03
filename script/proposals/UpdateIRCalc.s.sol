// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { BaseProposal } from "script/proposals/BaseProposal.sol";
import { ResupplyPairDeployer } from "src/protocol/ResupplyPairDeployer.sol";

contract UpdateIRCalc is BaseAction, BaseProposal {
    address public constant NEW_RATE_CALCULATOR = 0xD3d5C6fc52f3bc29C3aB017d57D9A94A036Ca90f;

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

        address pairDeployer = registry.getAddress("PAIR_DEPLOYER");
        ResupplyPairDeployer.ConfigData memory config = ResupplyPairDeployer(pairDeployer).defaultConfigData();

        actions = new IVoter.Action[](numPairs + 1);
        actions[0] = IVoter.Action({
            target: pairDeployer,
            data: abi.encodeWithSelector(
                ResupplyPairDeployer.setDefaultConfigData.selector,
                config.oracle,
                rateCalculator,
                config.maxLTV,
                config.initialBorrowLimit,
                config.liquidationFee,
                config.mintFee,
                config.protocolRedemptionFee
            )
        });
        for (uint256 i = 0; i < pairs.length; i++) {
            actions[i + 1] = IVoter.Action({
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
