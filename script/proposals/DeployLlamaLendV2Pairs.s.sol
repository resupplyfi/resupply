// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol } from "src/Constants.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { BaseProposal } from "script/proposals/BaseProposal.sol";

contract DeployLlamaLendV2Pairs is BaseProposal {
    string public constant DESCRIPTION = "Deploy and register Resupply pairs for Curve LlamaLend v2 sDOLA/crvUSD and sfrxUSD/crvUSD lender vaults";

    address public constant SDOLA_VAULT = 0x2b5a321C3cb1F33e1ABECD047C2649D0b4C47eBa;
    address public constant SFRXUSD_VAULT = 0x3Da0F110079012387F47C6Fc6e878F10262E300a;

    function run() public isBatch(deployer) {
        IVoter.Action[] memory actions = buildProposalCalldata();
        printCallData(actions);
        proposeVote(actions, DESCRIPTION);

        deployMode = DeployMode.PRODUCTION;
        if (deployMode == DeployMode.PRODUCTION) executeBatch(true);
    }

    function buildProposalCalldata() public override returns (IVoter.Action[] memory actions) {
        (address sdolaPair, bytes memory deploySdolaPair) = getPairDeploymentAddressAndCallData(Protocol.PROTOCOL_ID_CURVE, SDOLA_VAULT, address(0), 0);
        (address sfrxUsdPair, bytes memory deploySfrxUsdPair) = getPairDeploymentAddressAndCallData(Protocol.PROTOCOL_ID_CURVE, SFRXUSD_VAULT, address(0), 0);

        actions = new IVoter.Action[](4);
        actions[0] = IVoter.Action({ target: address(pairDeployer), data: deploySdolaPair });
        actions[1] = IVoter.Action({ target: Protocol.REGISTRY, data: getAddPairToRegistryCallData(sdolaPair) });
        actions[2] = IVoter.Action({ target: address(pairDeployer), data: deploySfrxUsdPair });
        actions[3] = IVoter.Action({ target: Protocol.REGISTRY, data: getAddPairToRegistryCallData(sfrxUsdPair) });
    }
}
