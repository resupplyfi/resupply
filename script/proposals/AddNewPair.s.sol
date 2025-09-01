pragma solidity 0.8.28;

import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { Protocol, Mainnet } from "src/Constants.sol";
import { console } from "lib/forge-std/src/console.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { BaseProposal } from "script/proposals/BaseProposal.sol";

contract AddNewPair is BaseAction, BaseProposal {
    uint256 public constant MAX_DISTRIBUTION_PER_SECOND_PER_ASSET = uint256(2e17) / 365 days; // 20% apr max distribution rate;
    uint256 public constant PROTOCOL_ID = Protocol.PROTOCOL_ID_CURVE;
    address public constant COLLATERAL = 0x7430f11Eeb64a4ce50C8f92177485d34C48DA72c;
    address public constant STAKING = PROTOCOL_ID == Protocol.PROTOCOL_ID_CURVE ? Mainnet.CONVEX_BOOSTER : address(0);
    uint256 public constant STAKING_ID = 483;
    uint256 public constant TARGET_BORROW_LIMIT = 10_000_000e18;

    function run() public isBatch(deployer) {
        IVoter.Action[] memory data = buildProposalCalldata();
        proposeVote(data, "Onboard fxSAVE-long LlamaLend Market. https://gov.resupply.fi/t/onboard-fxsave-long-llamalend-market/73");

        deployMode = DeployMode.PRODUCTION;
        if (deployMode == DeployMode.PRODUCTION) {
            executeBatch(true);
        }
    }

    function buildProposalCalldata() public override returns (IVoter.Action[] memory actions) {
        (address pair, bytes memory deployCalldata) = getPairDeploymentAddressAndCallData(
            PROTOCOL_ID,    // protocol id
            COLLATERAL,     // collateral
            STAKING,        // staking
            STAKING_ID      // staking id
        );
        bytes memory addPairData = getAddPairToRegistryCallData(pair); // pair
        bytes memory rampBorrowLimitData = getRampBorrowLimitCallData(
            pair, 
            TARGET_BORROW_LIMIT, // new borrow limit
            block.timestamp + 20 days // end time (needs buffer for proposal to be voted+executed)
        );

        actions = new IVoter.Action[](3);

        // deploy pair
        actions[0] = IVoter.Action({
            target: address(pairDeployer),
            data: deployCalldata
        });
        // add pair to registry
        actions[1] = IVoter.Action({
            target: Protocol.REGISTRY,
            data: addPairData
        });
        // ramp borrow limit
        actions[2] = IVoter.Action({
            target: Protocol.BORROW_LIMIT_CONTROLLER,
            data: rampBorrowLimitData
        });
        return actions;
    }
}