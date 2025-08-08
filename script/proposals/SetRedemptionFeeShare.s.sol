// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "src/Constants.sol" as Constants;
import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { Protocol } from "src/Constants.sol";
import { console } from "lib/forge-std/src/console.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";

interface IPermastakerOperator {
    function safeExecute(address target, bytes calldata data) external;
    function createNewProposal(IVoter.Action[] calldata actions, string calldata description) external;
}

contract SetRedemptionFeeShare is BaseAction {
    address public constant deployer = 0x4444AAAACDBa5580282365e25b16309Bd770ce4a;
    IPermastakerOperator public constant PERMA_STAKER_OPERATOR = IPermastakerOperator(0x3419b3FfF84b5FBF6Eec061bA3f9b72809c955Bf);
    address[] public pairs;
    IResupplyRegistry public constant registry = IResupplyRegistry(Protocol.REGISTRY);

    function run() public isBatch(deployer) {
        deployMode = DeployMode.FORK;

        pairs = registry.getAllPairAddresses();
        IVoter.Action[] memory data = buildCalldata();
        proposeVote(data);
        
        if (deployMode == DeployMode.PRODUCTION){
            executeBatch(true);
        } 
    }

    function buildCalldata() public returns (IVoter.Action[] memory actions) {
        actions = new IVoter.Action[](pairs.length);
        uint256 prevProtocolRedemptionFee;
        uint256 newProtocolRedemptionFee = 0.2e18;
        for (uint256 i = 0; i < pairs.length; i++) {
            // IResupplyPair(pairs[i]).setProtocolRedemptionFee(newProtocolRedemptionFee);
            prevProtocolRedemptionFee = IResupplyPair(pairs[i]).protocolRedemptionFee();
            actions[i] = IVoter.Action({
                target: pairs[i],
                data: abi.encodeWithSelector(
                    IResupplyPair.setProtocolRedemptionFee.selector,
                    newProtocolRedemptionFee
                )
            });
            require(newProtocolRedemptionFee < prevProtocolRedemptionFee, "Fee too high");
        }
        
        console.log("Number of actions:", actions.length);
    }

    function proposeVote(IVoter.Action[] memory actions) public {
        addToBatch(
            address(PERMA_STAKER_OPERATOR),
            abi.encodeWithSelector(
                IPermastakerOperator.createNewProposal.selector,
                actions,
                "Set borrower redemption fee share to 80%; protocol share to 20%"
            )
        );
    }
}
