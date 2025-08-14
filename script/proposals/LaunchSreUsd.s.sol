pragma solidity 0.8.28;

import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { Protocol } from "src/Constants.sol";
import { console } from "lib/forge-std/src/console.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { SavingsReUSD } from "src/protocol/sreusd/sreUSD.sol";
import { IFeeDeposit } from "src/interfaces/IFeeDeposit.sol";
import { IRewardHandler } from "src/interfaces/IRewardHandler.sol";
import { ISimpleReceiver } from "src/interfaces/ISimpleReceiver.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IGovStaker } from "src/interfaces/IGovStaker.sol";
import { BaseProposal } from "script/proposals/BaseProposal.sol";

contract LaunchSreUsd is BaseAction, BaseProposal {
    uint256 public constant MAX_DISTRIBUTION_PER_SECOND_PER_ASSET = uint256(2e17) / 365 days; // 20% apr max distribution rate;

    function run() public isBatch(deployer) {
        IVoter.Action[] memory data = buildProposalCalldata();
        proposeVote(data, "Launch sreUSD");
    }

    function buildProposalCalldata() public returns (IVoter.Action[] memory actions) {
        actions = new IVoter.Action[](9 + numPairs);
        // sreUSD.setMaxDistributionPerSecondPerAsset(MAX_DISTRIBUTION_PER_SECOND_PER_ASSET)
        actions[0] = IVoter.Action({
            target: Protocol.SREUSD,
            data: abi.encodeWithSelector(
                SavingsReUSD.setMaxDistributionPerSecondPerAsset.selector, 
                MAX_DISTRIBUTION_PER_SECOND_PER_ASSET)
        });
        console.log("Number of actions:", actions.length);
        // feeDeposit.setOperator(feeDepositController)
        actions[1] = IVoter.Action({
            target: Protocol.FEE_DEPOSIT,
            data: abi.encodeWithSelector(
                IFeeDeposit.setOperator.selector,
                address(Protocol.FEE_DEPOSIT_CONTROLLER)
            )
        });
        // newRewardHandler.migrateState(oldRewardHandler, true, true)
        actions[2] = IVoter.Action({
            target: Protocol.REWARD_HANDLER,
            data: abi.encodeWithSelector(
                IRewardHandler.migrateState.selector,
                Protocol.REWARD_HANDLER_OLD,
                true,
                true
            )
        });
        // debtReceiver.setApprovedClaimer(oldRewardHandler, false) // revoke old reward handler
        actions[3] = IVoter.Action({
            target: Protocol.DEBT_RECEIVER,
            data: abi.encodeWithSelector(
                ISimpleReceiver.setApprovedClaimer.selector,
                Protocol.REWARD_HANDLER_OLD,
                false
            )
        });
        // insuranceEmissionsReceiver.setApprovedClaimer(oldRewardHandler, false) // revoke old reward handler
        actions[4] = IVoter.Action({
            target: Protocol.INSURANCE_POOL_RECEIVER,
            data: abi.encodeWithSelector(
                ISimpleReceiver.setApprovedClaimer.selector,
                Protocol.REWARD_HANDLER_OLD,
                false
            )
        });
        // debtReceiver.setApprovedClaimer(newRewardHandler, true) // approve new reward handler
        actions[5] = IVoter.Action({
            target: Protocol.DEBT_RECEIVER,
            data: abi.encodeWithSelector(
                ISimpleReceiver.setApprovedClaimer.selector,
                Protocol.REWARD_HANDLER,
                true
            )
        });
        // insuranceEmissionsReceiver.setApprovedClaimer(newRewardHandler, true) // approve new reward handler
        actions[6] = IVoter.Action({
            target: Protocol.INSURANCE_POOL_RECEIVER,
            data: abi.encodeWithSelector(
                ISimpleReceiver.setApprovedClaimer.selector,
                Protocol.REWARD_HANDLER,
                true
            )
        });
        // registry.setRewardHandler(newRewardHandler) // set new reward handler
        actions[7] = IVoter.Action({
            target: Protocol.REGISTRY,
            data: abi.encodeWithSelector(
                IResupplyRegistry.setRewardHandler.selector,
                Protocol.REWARD_HANDLER
            )
        });
        // staker.setRewardsDistributor(stablecoin, newRewardHandler) // set new reward handler
        actions[8] = IVoter.Action({
            target: Protocol.GOV_STAKER,
            data: abi.encodeWithSelector(
                IGovStaker.setRewardsDistributor.selector,
                Protocol.STABLECOIN,
                Protocol.REWARD_HANDLER
            )
        });

        for (uint256 i = 0; i < pairs.length; i++) {
            // IResupplyPair(pairs[i]).setRateCalculator(address(calcv2),true);
            actions[i + 9] = IVoter.Action({
                target: pairs[i],
                data: abi.encodeWithSelector(
                    IResupplyPair.setRateCalculator.selector,
                    Protocol.INTEREST_RATE_CALCULATOR_V2,
                    true //add interest BEFORE switching
                )
            });
        }
    }
}