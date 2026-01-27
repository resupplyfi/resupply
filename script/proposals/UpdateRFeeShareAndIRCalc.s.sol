pragma solidity 0.8.28;

import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { Protocol } from "src/Constants.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { BaseProposal } from "script/proposals/BaseProposal.sol";
import { ResupplyPairDeployer } from "src/protocol/ResupplyPairDeployer.sol";

contract UpdateRFeeShareAndIRCalc is BaseAction, BaseProposal {
    uint256 public prevProtocolRedemptionFee;
    uint256 public newProtocolRedemptionFee = 0.05e18;

    function run() public isBatch(deployer) {
        IVoter.Action[] memory data = buildProposalCalldata();
        proposeVote(data, "Update Redemption Fee Split and Interest Rate Calculator");

        deployMode = DeployMode.FORK;
        if (deployMode == DeployMode.PRODUCTION) {
            executeBatch(true);
        }
    }

    function buildProposalCalldata() public override returns (IVoter.Action[] memory actions) {
        address pairDeployer = registry.getAddress("PAIR_DEPLOYER");
        ResupplyPairDeployer.ConfigData memory config = ResupplyPairDeployer(pairDeployer).defaultConfigData();
        actions = new IVoter.Action[](numPairs * 2 + 1);
        actions[0] = IVoter.Action({
            target: pairDeployer,
            data: abi.encodeWithSelector(
                ResupplyPairDeployer.setDefaultConfigData.selector,
                config.oracle,
                Protocol.INTEREST_RATE_CALCULATOR_V2_1,
                config.maxLTV,
                config.initialBorrowLimit,
                config.liquidationFee,
                config.mintFee,
                config.protocolRedemptionFee
            )
        });
        for (uint256 i = 0; i < pairs.length; i++) {
            // Update redemption fee share
            prevProtocolRedemptionFee = IResupplyPair(pairs[i]).protocolRedemptionFee();
            uint256 index = 1 + i * 2;
            actions[index] = IVoter.Action({
                target: pairs[i],
                data: abi.encodeWithSelector(
                    IResupplyPair.setProtocolRedemptionFee.selector,
                    newProtocolRedemptionFee
                )
            });
            require(newProtocolRedemptionFee < prevProtocolRedemptionFee, "Fee too high");

            actions[index + 1] = IVoter.Action({
                target: pairs[i],
                data: abi.encodeWithSelector(
                    IResupplyPair.setRateCalculator.selector,
                    Protocol.INTEREST_RATE_CALCULATOR_V2_1,
                    true
                )
            });
        }
    }
}
