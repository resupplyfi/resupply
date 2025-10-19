pragma solidity 0.8.28;

import { Protocol, Mainnet } from "src/Constants.sol";
import { console } from "lib/forge-std/src/console.sol";
import { BaseCurveProposal } from "script/proposals/curve/BaseCurveProposal.sol";
import { IInflationaryVest } from 'src/interfaces/curve/IInflationaryVest.sol';


contract YBEmissionsRecipient is BaseCurveProposal {

    address public deployer = Mainnet.CONVEX_DEPLOYER;

    address public inflationaryVest = 0x36e36D5D588D480A15A40C7668Be52D36eb206A8;
    address public recipient = 0x0997f89c451124EadF00f87DE77924D77A38419a;

    function run() public {

        vm.startBroadcast(deployer);
        bytes memory actions = buildProposalScript();
        console.logBytes(actions);

        proposeOwnershipVote(actions, "Set recipient ");
    }

    function buildProposalScript() public override returns (bytes memory script) {
        BaseCurveProposal.Action[] memory actions = new BaseCurveProposal.Action[](1);

        actions[0] = BaseCurveProposal.Action({
            target: inflationaryVest,
            data: abi.encodeWithSelector(
                IInflationaryVest.set_recipient.selector, 
                recipient
            )
        });

        console.log("Number of actions:", actions.length);
        console.log("inflationary vest at: ", inflationaryVest);
        console.log("recipient at: ", recipient);

        return buildScript(Mainnet.CURVE_OWNERSHIP_AGENT, actions);
    }
}