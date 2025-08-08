// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "src/Constants.sol" as Constants;
import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { Protocol } from "src/Constants.sol";
import { console } from "lib/forge-std/src/console.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { IEmissionsController } from "src/interfaces/IEmissionsController.sol";
import { ITreasury } from "src/interfaces/ITreasury.sol";
import { RetentionIncentives } from "src/dao/RetentionIncentives.sol";
import { RetentionReceiver } from "src/dao/emissions/receivers/RetentionReceiver.sol";

interface IPermastakerOperator {
    function safeExecute(address target, bytes calldata data) external;
    function createNewProposal(IVoter.Action[] calldata actions, string calldata description) external;
}

contract LaunchRetentionIncentives is BaseAction {
    address public constant deployer = 0x4444AAAACDBa5580282365e25b16309Bd770ce4a;
    uint256 public constant TREASURY_WEEKLY_ALLOCATION = 34_255e18;
    IPermastakerOperator public constant PERMA_STAKER_OPERATOR = IPermastakerOperator(0x3419b3FfF84b5FBF6Eec061bA3f9b72809c955Bf);
    IEmissionsController public emissionsController = IEmissionsController(Protocol.EMISSIONS_CONTROLLER);

    function run() public isBatch(deployer) {
        deployMode = DeployMode.FORK;
        
        IVoter.Action[] memory data = buildCalldata();
        proposeVote(data);
        if (deployMode == DeployMode.PRODUCTION){
            // RetentionIncentives and RetentionReceiver should be deployed before running this script
            require(Protocol.RETENTION_INCENTIVES.code.length > 0, "RetentionIncentives not deployed");
            require(Protocol.RETENTION_RECEIVER.code.length > 0, "RetentionReceiver not deployed");
            executeBatch(true);
        } 
    }

    function buildCalldata() public returns (IVoter.Action[] memory actions) {
        actions = new IVoter.Action[](4);
        
        // 1. retentionIncentives.setRewardHandler(retentionReceiver)
        actions[0] = IVoter.Action({
            target: Protocol.RETENTION_INCENTIVES,
            data: abi.encodeWithSelector(
                RetentionIncentives.setRewardHandler.selector,
                Protocol.RETENTION_RECEIVER
            )
        });

        uint256 nextReceiverId = emissionsController.nextReceiverId();
        require(nextReceiverId == 3, "Receiver IDs are not sequential");        
        // 2. emissionsController.registerReceiver(retentionReceiver)
        actions[1] = IVoter.Action({
            target: Protocol.EMISSIONS_CONTROLLER,
            data: abi.encodeWithSelector(
                IEmissionsController.registerReceiver.selector,
                Protocol.RETENTION_RECEIVER
            )
        });
        
        // 3. emissionsController.setReceiverWeights([debt, ip, liq, retention], [1875, 2500, 5000, 625])
        uint256[] memory receivers = new uint256[](4);
        receivers[0] = emissionsController.receiverToId(Protocol.DEBT_RECEIVER);
        receivers[1] = emissionsController.receiverToId(Protocol.INSURANCE_POOL_RECEIVER);
        receivers[2] = emissionsController.receiverToId(Protocol.LIQUIDITY_INCENTIVES_RECEIVER);
        receivers[3] = nextReceiverId;
        
        uint256[] memory weights = new uint256[](4);
        weights[0] = 1875; // Debt receiver
        weights[1] = 2500; // Insurance pool emissions
        weights[2] = 5000; // Liquidity emissions
        weights[3] = 625;  // Retention incentives
        
        actions[2] = IVoter.Action({
            target: Protocol.EMISSIONS_CONTROLLER,
            data: abi.encodeWithSelector(
                IEmissionsController.setReceiverWeights.selector,
                receivers,
                weights
            )
        });
        
        // 4. treasury.setTokenApproval(govToken, retentionReceiver, type(uint256).max)
        actions[3] = IVoter.Action({
            target: Protocol.TREASURY,
            data: abi.encodeWithSelector(
                ITreasury.setTokenApproval.selector,
                Protocol.GOV_TOKEN,
                Protocol.RETENTION_RECEIVER,
                type(uint256).max
            )
        });
        
        console.log("Number of actions:", actions.length);
    }

    function proposeVote(IVoter.Action[] memory actions) public {
        addToBatch(
            address(PERMA_STAKER_OPERATOR),
            abi.encodeWithSelector(
                IPermastakerOperator.createNewProposal.selector,
                actions,
                "Launch Retention Incentives"
            )
        );
    }
}
