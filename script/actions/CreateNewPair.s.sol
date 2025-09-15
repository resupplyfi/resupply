pragma solidity 0.8.28;

import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { Protocol, Mainnet } from "src/Constants.sol";
import { console } from "lib/forge-std/src/console.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { BaseProposal } from "script/proposals/BaseProposal.sol";
import { IResupplyPairDeployer } from "src/interfaces/IResupplyPairDeployer.sol";

contract CreateNewPair is BaseAction {
    uint256 public constant PROTOCOL_ID = Protocol.PROTOCOL_ID_CURVE;
    address public constant COLLATERAL = 0xb89aF59FfD0c2Bf653F45B60441B875027696733;
    address public constant STAKING = PROTOCOL_ID == Protocol.PROTOCOL_ID_CURVE ? Mainnet.CONVEX_BOOSTER : address(0);
    uint256 public constant STAKING_ID = 493;

    function run() public isBatch(Protocol.DEPLOYER) {
        deployMode = DeployMode.PRODUCTION;

        address pair = pairDeployer.predictPairAddress(
            PROTOCOL_ID,
            COLLATERAL,
            STAKING,
            STAKING_ID
        );
        console.log("pair deployed at", pair);

        addToBatch(
            address(pairDeployer),
            abi.encodeWithSelector(
                pairDeployer.deployWithDefaultConfig.selector,
                PROTOCOL_ID,
                COLLATERAL,
                STAKING,
                STAKING_ID
            )
        );

        if (deployMode == DeployMode.PRODUCTION) {
            executeBatch(true);
        }
    }
}