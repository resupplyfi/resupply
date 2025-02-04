// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

// import { BaseScript } from "frax-std/BaseScript.sol";
// import { console } from "frax-std/FraxTest.sol";
import { TenderlyHelper } from "../utils/TenderlyHelper.s.sol";
import { console } from "lib/forge-std/src/console.sol";
import "src/Constants.sol" as Constants;
import { DeployScriptReturn } from "./DeployScriptReturn.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ResupplyRegistry } from "src/protocol/ResupplyRegistry.sol";
import { ResupplyPairDeployer } from "src/protocol/ResupplyPairDeployer.sol";
import { Stablecoin } from "src/protocol/Stablecoin.sol";
import { InterestRateCalculator } from "src/protocol/InterestRateCalculator.sol";
import { BasicVaultOracle } from "src/protocol/BasicVaultOracle.sol";
import { ResupplyPair } from "src/protocol/ResupplyPair.sol";
import { InsurancePool } from "src/protocol/InsurancePool.sol";
import { SimpleRewardStreamer } from "src/protocol/SimpleRewardStreamer.sol";
import { FeeDeposit } from "src/protocol/FeeDeposit.sol";
import { FeeDepositController } from "src/protocol/FeeDepositController.sol";
import { RedemptionHandler } from "src/protocol/RedemptionHandler.sol";
import { LiquidationHandler } from "src/protocol/LiquidationHandler.sol";
import { RewardHandler } from "src/protocol/RewardHandler.sol";
import { TestOFT } from "src/test/TestOFT.sol";
import { ILayerZeroEndpointV2 } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";



contract DeployTestToken is TenderlyHelper {
    uint256 internal constant DEFAULT_MAX_LTV = 95_000; // 95% with 1e5 precision
    uint256 internal constant DEFAULT_LIQ_FEE = 5_000; // 5% with 1e5 precision
    uint256 internal constant DEFAULT_BORROW_LIMIT = 5_000_000 * 1e18;
    uint256 internal constant DEFAULT_MINT_FEE = 0; //1e5 prevision
    uint256 internal constant DEFAULT_PROTOCOL_REDEMPTION_FEE = 1e18 / 2; //half

    function run() external returns (DeployScriptReturn[] memory _return) {
        address deployer = vm.rememberKey(vm.envUint("PK"));
        console.log(">>> deploying from:", deployer);
        vm.startBroadcast(deployer);
        setEthBalance(deployer, 10 ether);
        _return = deployEnvironment(deployer);
    }

    function setReturnData(address _address, bytes memory _constructor, string memory _name) private returns(DeployScriptReturn memory _return){
        _return.address_ = _address;
        _return.constructorParams = _constructor;
        _return.contractName = _name;
    }

    function addressToBytes32(address _addr) public pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }

    function deployEnvironment(address deployer) private returns (DeployScriptReturn[] memory _return) {
        _return = new DeployScriptReturn[](1);

        address _core = deployer;

        TestOFT _token = new TestOFT(_core);
        console.log("owner/core: ", _token.owner());
        _token.setOperator(deployer,true);

        _token.faucet(1_000 * 1e18);
        
        ILayerZeroEndpointV2 endpoint = ILayerZeroEndpointV2(0x1a44076050125825900e736c501f859c50fE728c);
        _token.setPeer(252, addressToBytes32(address(_token)));

        console.log("======================================");
        console.log("    Contracts     ");
        console.log("======================================");
        for(uint256 i=0; i < _return.length; i++){
            console.log(_return[i].contractName,": ", _return[i].address_);
        }
        console.log("======================================");
        console.log("balance of token: ", _token.balanceOf(deployer));
    }
}