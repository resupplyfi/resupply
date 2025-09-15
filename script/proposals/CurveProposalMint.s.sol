pragma solidity 0.8.28;

import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { Protocol, Mainnet } from "src/Constants.sol";
import { console } from "lib/forge-std/src/console.sol";
import { BaseCurveProposal } from "script/proposals/BaseCurveProposal.sol";
import { ICrvusdController } from 'src/interfaces/ICrvusdController.sol';

contract CurveProposalMint is BaseAction, BaseCurveProposal {

    address public deployer = Mainnet.CONVEX_DEPLOYER;

    address public lendfactory;
    address public market;

    function run() public isBatch(deployer) {
        vm.startBroadcast(deployer);
        bytes memory actions = buildProposalScript();

        proposeOwnershipVote(actions, "Test proposal");

        deployMode = DeployMode.FORK;
        if (deployMode == DeployMode.PRODUCTION) {
            executeBatch(true);
        }
    }

    function setDeployAddresses(address _factory, address _market) public{
        lendfactory = _factory;
        market = _market;
    }

    function buildProposalScript() public override returns (bytes memory script) {
        BaseCurveProposal.Action[] memory actions = new BaseCurveProposal.Action[](1);

        actions[0] = BaseCurveProposal.Action({
            target: Mainnet.CURVE_CRVUSD_CONTROLLER,
            data: abi.encodeWithSelector(
                ICrvusdController.set_debt_ceiling.selector, 
                lendfactory,
                5_000_000e18)
        });

        console.log("Number of actions:", actions.length);

        return buildScript(Mainnet.CURVE_OWNERSHIP_AGENT, actions);
    }
}