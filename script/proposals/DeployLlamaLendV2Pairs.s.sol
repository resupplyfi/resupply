// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Mainnet, Protocol } from "src/Constants.sol";
import { IResupplyPairDeployer } from "src/interfaces/IResupplyPairDeployer.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { BaseProposal } from "script/proposals/BaseProposal.sol";

contract DeployLlamaLendV2Pairs is BaseProposal {
    string public constant DESCRIPTION = "Add CurveLendV2 support and deploy and register the sDOLA/crvUSD and sfrxUSD/crvUSD pairs";

    string public constant PROTOCOL_NAME = "CurveLendV2";
    uint256 public constant AMOUNT_TO_BURN = 1e18;
    uint256 public constant MIN_SHARE_BURN_AMOUNT = 1e20;
    bytes4 public constant BORROW_TOKEN_SELECTOR = 0x38d52e0f; // asset()
    bytes4 public constant COLLATERAL_TOKEN_SELECTOR = 0x2621db2f; // collateral_token()

    address public constant SDOLA_VAULT = 0x2b5a321C3cb1F33e1ABECD047C2649D0b4C47eBa;
    address public constant SFRXUSD_VAULT = 0x3Da0F110079012387F47C6Fc6e878F10262E300a;
    uint256 public constant SDOLA_CONVEX_PID = 570;
    uint256 public constant SFRXUSD_CONVEX_PID = 571;

    // The new protocol ID does not exist until action 0 executes, so the
    // factory cannot predict these addresses while this proposal is built.
    // The constants are CREATE2 predictions verified in the proposal test.
    address public constant SDOLA_PAIR = 0xEcceF525b3063705DA5075a1ce5De1892D24C25A;
    address public constant SFRXUSD_PAIR = 0x0837E20D15585B4cA5c1a3fCedCCF8f72855Cb56;

    function run() public isBatch(deployer) {
        IVoter.Action[] memory actions = buildProposalCalldata();
        printCallData(actions);
        proposeVote(actions, DESCRIPTION);

        deployMode = DeployMode.PRODUCTION;
        if (deployMode == DeployMode.PRODUCTION) executeBatch(true);
    }

    function buildProposalCalldata() public override returns (IVoter.Action[] memory actions) {
        require(
            pairDeployer.supportedProtocolsLength() ==
                Protocol.PROTOCOL_ID_CURVE_V2,
            "unexpected next protocol ID"
        );

        bytes memory addProtocol = abi.encodeWithSelector(
            IResupplyPairDeployer.addSupportedProtocol.selector,
            PROTOCOL_NAME,
            AMOUNT_TO_BURN,
            MIN_SHARE_BURN_AMOUNT,
            BORROW_TOKEN_SELECTOR,
            COLLATERAL_TOKEN_SELECTOR
        );
        bytes memory deploySdolaPair = abi.encodeWithSelector(
            IResupplyPairDeployer.deployWithDefaultConfig.selector,
            Protocol.PROTOCOL_ID_CURVE_V2,
            SDOLA_VAULT,
            Mainnet.CONVEX_BOOSTER,
            SDOLA_CONVEX_PID
        );
        bytes memory deploySfrxUsdPair = abi.encodeWithSelector(
            IResupplyPairDeployer.deployWithDefaultConfig.selector,
            Protocol.PROTOCOL_ID_CURVE_V2,
            SFRXUSD_VAULT,
            Mainnet.CONVEX_BOOSTER,
            SFRXUSD_CONVEX_PID
        );

        actions = new IVoter.Action[](5);
        actions[0] = IVoter.Action({ target: address(pairDeployer), data: addProtocol });
        actions[1] = IVoter.Action({ target: address(pairDeployer), data: deploySdolaPair });
        actions[2] = IVoter.Action({ target: Protocol.REGISTRY, data: getAddPairToRegistryCallData(SDOLA_PAIR) });
        actions[3] = IVoter.Action({ target: address(pairDeployer), data: deploySfrxUsdPair });
        actions[4] = IVoter.Action({ target: Protocol.REGISTRY, data: getAddPairToRegistryCallData(SFRXUSD_PAIR) });
    }
}
