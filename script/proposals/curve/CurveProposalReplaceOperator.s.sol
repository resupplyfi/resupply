pragma solidity 0.8.28;

import { Protocol, Mainnet } from "src/Constants.sol";
import { console } from "lib/forge-std/src/console.sol";
import { BaseCurveProposal } from "script/proposals/curve/BaseCurveProposal.sol";
import { ICrvusdController } from 'src/interfaces/ICrvusdController.sol';
import { ICurveLendMinterFactory } from 'src/interfaces/ICurveLendMinterFactory.sol';
import { ICurveLendOperator } from "src/interfaces/curve/ICurveLendOperator.sol";


contract CurveProposalReplaceOperator is BaseCurveProposal {
    address public constant OLD_OPERATOR = 0x6119e210E00d4BE2Df1B240D82B1c3DECEdbBBf0;
    address public deployer = Mainnet.CONVEX_DEPLOYER;

    address public market;
    address public newimplementation;

    function run() public {

        newimplementation = address(0xB64e295a69928d3404E576a8fF3c8766559cB8F5);
        market = Mainnet.CURVELEND_SREUSD_CRVUSD;

        vm.startBroadcast(deployer);
        bytes memory actions = buildProposalScript();

        string memory metadata = "Update lending operator implementation. Increase lending to sreusd market to 15m.";
        console.log("meta: ", metadata);
        proposeOwnershipVote(actions, metadata);
    }

    function setDeployAddresses(address _market, address _newimp) public{
        market = _market;
        newimplementation = _newimp;
    }

    function buildProposalScript() public override returns (bytes memory script) {
        BaseCurveProposal.Action[] memory actions = new BaseCurveProposal.Action[](6);

        //update implementation
        actions[0] = BaseCurveProposal.Action({
            target: Mainnet.CURVE_LENDING_FACTORY,
            data: abi.encodeWithSelector(
                ICurveLendMinterFactory.setImplementation.selector, 
                newimplementation)
        });

        //mint more for new operator
        actions[1] = BaseCurveProposal.Action({
            target: Mainnet.CURVE_CRVUSD_CONTROLLER,
            data: abi.encodeWithSelector(
                ICrvusdController.set_debt_ceiling.selector, 
                Mainnet.CURVE_LENDING_FACTORY,
                20_000_000e18)
        });

        //create new operator and fund
        actions[2] = BaseCurveProposal.Action({
            target: Mainnet.CURVE_LENDING_FACTORY,
            data: abi.encodeWithSelector(
                ICurveLendMinterFactory.addMarketOperator.selector, 
                market,
                15_000_000e18)
        });

        //withdraw profit from old operator withdraw_profit()
        // actions[3] = BaseCurveProposal.Action({
        //     target: OLD_OPERATOR,
        //     data: abi.encodeWithSelector(
        //         ICurveLendOperator.withdraw_profit.selector
        //     )
        // });

        //reduce old operator cap to 0 setMintLimit(uint256)
        actions[3] = BaseCurveProposal.Action({
            target: OLD_OPERATOR,
            data: abi.encodeWithSelector(
                ICurveLendOperator.setMintLimit.selector, 
                0
            )
        });

        //reduce old operator active amount to 0 reduceAmount(uint256)
        actions[4] = BaseCurveProposal.Action({
            target: OLD_OPERATOR,
            data: abi.encodeWithSelector(
                ICurveLendOperator.reduceAmount.selector, 
                5_000_000e18)
        });

        //return debt ceiling back to 10m
        actions[5] = BaseCurveProposal.Action({
            target: Mainnet.CURVE_CRVUSD_CONTROLLER,
            data: abi.encodeWithSelector(
                ICrvusdController.set_debt_ceiling.selector, 
                Mainnet.CURVE_LENDING_FACTORY,
                15_000_000e18)
        });

        console.log("Number of actions:", actions.length);
        console.log("new impl:", newimplementation);
        console.log("lend factory at: ", Mainnet.CURVE_LENDING_FACTORY);
        console.log("lend market at: ", market);

        return buildScript(Mainnet.CURVE_OWNERSHIP_AGENT, actions);
    }
}