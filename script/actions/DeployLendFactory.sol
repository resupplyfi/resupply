pragma solidity 0.8.28;

import { Protocol, Mainnet } from "src/Constants.sol";
import {Script} from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { console2 } from "forge-std/console2.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { CurveLendOperator } from "src/dao/CurveLendOperator.sol";
import { CurveLendMinterFactory } from "src/dao/CurveLendMinterFactory.sol";
import { ICrvusdController } from 'src/interfaces/ICrvusdController.sol';

contract DeployLendFactory is Script {
    address public constant deployer = Protocol.DEPLOYER;
    address public constant TREASURY = Protocol.TREASURY;

    IERC20 public crvusd = IERC20(Mainnet.CRVUSD_ERC20);

    function run() public {

        vm.startBroadcast();

        //deploy implementation and factory
        CurveLendOperator lenderImpl = new CurveLendOperator();

        ICrvusdController crvusdController = ICrvusdController(Mainnet.CURVE_CRVUSD_CONTROLLER);
        address feeReceiver = crvusdController.fee_receiver();

        CurveLendMinterFactory factory = new CurveLendMinterFactory(
            Mainnet.CURVE_OWNERSHIP_AGENT,
            address(crvusdController),
            feeReceiver,
            address(lenderImpl)
        );

        console.log("deployer: ", msg.sender);
        console.log("factory address: ", address(factory));
        console.log("impl address: ", address(lenderImpl));

        vm.stopBroadcast();

    }

}