pragma solidity 0.8.28;

import { Protocol, Mainnet } from "src/Constants.sol";
import { console } from "lib/forge-std/src/console.sol";
import { BaseCurveProposal } from "script/proposals/curve/BaseCurveProposal.sol";
import { ICrvusdController } from 'src/interfaces/ICrvusdController.sol';
import { ICurveLendMinterFactory } from 'src/interfaces/ICurveLendMinterFactory.sol';
import { CurveLendOperator } from "src/dao/CurveLendOperator.sol";
import { CurveLendMinterFactory } from "src/dao/CurveLendMinterFactory.sol";

contract CurveProposalReplaceOperator is BaseCurveProposal {

    address public deployer = Mainnet.CONVEX_DEPLOYER;

    address public market;

    function run() public {

        market = Mainnet.CURVELEND_SREUSD_CRVUSD;

        vm.startBroadcast(deployer);
        bytes memory actions = buildProposalScript();

        string memory metadata = "Update lending operator implementation. Increase lending to sreusd market to 10m.";
        console.log("meta: ", metadata);
        proposeOwnershipVote(actions, metadata);
    }

    function setDeployAddresses(address _market) public{
        market = _market;
    }

    function buildProposalScript() public override returns (bytes memory script) {
        BaseCurveProposal.Action[] memory actions = new BaseCurveProposal.Action[](6);

        address newimplementation = address(0);//todo fill
        //update implementation
        actions[0] = BaseCurveProposal.Action({
            target: Mainnet.CURVE_LENDING_FACTORY,
            data: abi.encodeWithSelector(
                CurveLendMinterFactory.setImplementation.selector, 
                newimplementation)
        });

        //mint more for new operator
        actions[1] = BaseCurveProposal.Action({
            target: Mainnet.CURVE_CRVUSD_CONTROLLER,
            data: abi.encodeWithSelector(
                ICrvusdController.set_debt_ceiling.selector, 
                Mainnet.CURVE_LENDING_FACTORY,
                10_000_000e18)
        });

        //create new operator and fund
        actions[2] = BaseCurveProposal.Action({
            target: Mainnet.CURVE_LENDING_FACTORY,
            data: abi.encodeWithSelector(
                ICurveLendMinterFactory.addMarketOperator.selector, 
                market,
                10_000_000e18)
        });

        address oldoperator = address(0x6119e210E00d4BE2Df1B240D82B1c3DECEdbBBf0);

        //reduce old operator cap to 0 setMintLimit(uint256)
        actions[3] = BaseCurveProposal.Action({
            target: oldoperator,
            data: abi.encodeWithSelector(
                CurveLendOperator.setMintLimit.selector, 
                0)
        });

        //reduce old operator active amount to 0 reduceAmount(uint256)
        actions[4] = BaseCurveProposal.Action({
            target: oldoperator,
            data: abi.encodeWithSelector(
                CurveLendOperator.reduceAmount.selector, 
                0)
        });

        //burn the returned amount  ICrvusdController.set_debt_ceiling(0)
        actions[5] = BaseCurveProposal.Action({
            target: Mainnet.CURVE_CRVUSD_CONTROLLER,
            data: abi.encodeWithSelector(
                ICrvusdController.set_debt_ceiling.selector, 
                Mainnet.CURVE_LENDING_FACTORY,
                0)
        });

        console.log("Number of actions:", actions.length);
        console.log("lend factory at: ", Mainnet.CURVE_LENDING_FACTORY);
        console.log("lend market at: ", market);

        return buildScript(Mainnet.CURVE_OWNERSHIP_AGENT, actions);
    }
}