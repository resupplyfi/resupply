pragma solidity 0.8.28;

import { Protocol, Mainnet } from "src/Constants.sol";
import { console } from "lib/forge-std/src/console.sol";
import { BaseCurveProposal } from "script/proposals/curve/BaseCurveProposal.sol";
import { ICrvusdController } from 'src/interfaces/ICrvusdController.sol';
import { ICurveLendMinterFactory } from 'src/interfaces/ICurveLendMinterFactory.sol';


contract CurveProposalMint is BaseCurveProposal {

    address public deployer = Mainnet.CONVEX_DEPLOYER;

    address public lendfactory;
    address public market;

    function run() public {

        lendfactory = Mainnet.CURVE_LENDING_FACTORY;
        market = Mainnet.CURVELEND_SREUSD_CRVUSD;

        vm.startBroadcast(deployer);
        bytes memory actions = buildProposalScript();

        proposeOwnershipVote(actions, "Mint and lend 5m crvUSD to the sreUSD Lending Market");
    }

    function setDeployAddresses(address _factory, address _market) public{
        lendfactory = _factory;
        market = _market;
    }

    function buildProposalScript() public override returns (bytes memory script) {
        BaseCurveProposal.Action[] memory actions = new BaseCurveProposal.Action[](2);

        actions[0] = BaseCurveProposal.Action({
            target: Mainnet.CURVE_CRVUSD_CONTROLLER,
            data: abi.encodeWithSelector(
                ICrvusdController.set_debt_ceiling.selector, 
                lendfactory,
                5_000_000e18)
        });

        actions[1] = BaseCurveProposal.Action({
            target: lendfactory,
            data: abi.encodeWithSelector(
                ICurveLendMinterFactory.addMarketOperator.selector, 
                market,
                5_000_000e18)
        });

        console.log("Number of actions:", actions.length);
        console.log("lend factory at: ", lendfactory);
        console.log("lend market at: ", market);

        return buildScript(Mainnet.CURVE_OWNERSHIP_AGENT, actions);
    }
}