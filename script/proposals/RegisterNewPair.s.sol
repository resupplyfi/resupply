pragma solidity 0.8.28;

import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { Protocol } from "src/Constants.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { BaseProposal } from "script/proposals/BaseProposal.sol";

contract RegisterNewPair is BaseAction, BaseProposal {
    uint256 public constant MAX_DISTRIBUTION_PER_SECOND_PER_ASSET = uint256(2e17) / 365 days; // 20% apr max distribution rate;
    address public constant PAIR_ADDRESS = 0x5254d4f55559f9Ca38cAf40A508a5b60E9af3202;
    uint256 public constant TARGET_BORROW_LIMIT = 6_500_000e18;

    function run() public isBatch(deployer) {
        IVoter.Action[] memory data = buildProposalCalldata();
        printCallData(data);
        proposeVote(data, "Onboard sdeUSD-long LlamaLend Market. https://gov.resupply.fi/t/onboard-sdeusd-long-llamalend-market/74");

        deployMode = DeployMode.PRODUCTION;
        if (deployMode == DeployMode.PRODUCTION) {
            executeBatch(true);
        }
    }

    function buildProposalCalldata() public override returns (IVoter.Action[] memory actions) {
        bytes memory addPairData = getAddPairToRegistryCallData(PAIR_ADDRESS);
        bytes memory rampBorrowLimitData = getRampBorrowLimitCallData(
            PAIR_ADDRESS, 
            TARGET_BORROW_LIMIT, // new borrow limit
            block.timestamp + 20 days // end time (needs buffer for proposal to be voted+executed)
        );

        actions = new IVoter.Action[](2);
        // add pair to registry
        actions[0] = IVoter.Action({
            target: Protocol.REGISTRY,
            data: addPairData
        });
        // ramp borrow limit
        actions[1] = IVoter.Action({
            target: Protocol.BORROW_LIMIT_CONTROLLER,
            data: rampBorrowLimitData
        });
        return actions;
    }
}