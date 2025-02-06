// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

// import { BaseScript } from "frax-std/BaseScript.sol";
// import { console } from "frax-std/FraxTest.sol";
import { TenderlyHelper } from "../utils/TenderlyHelper.s.sol";
import { console } from "lib/forge-std/src/console.sol";
import "src/Constants.sol" as Constants;
// import { DeployScriptReturn } from "./DeployScriptReturn.sol";
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

import { CreateXDeployer } from "script/utils/CreateXDeployer.s.sol";


contract DeployTestToken is TenderlyHelper, CreateXDeployer {

    function run() external{
        address deployer = vm.rememberKey(vm.envUint("PK"));
        console.log(">>> deploying from:", deployer);
        vm.startBroadcast(deployer);
        // setEthBalance(deployer, 10 ether);
        deployEnvironment(deployer);
    }

    function addressToBytes32(address _addr) public pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }

    function deployEnvironment(address deployer) private{

        address _core = deployer;
        address tokendeployer = deployer; //change to test permission

        // TestOFT _token = new TestOFT(_core);

        bytes memory constructorArgs = abi.encode(address(_core));
        bytes memory bytecode = abi.encodePacked(vm.getCode("TestOFT.sol:TestOFT"), constructorArgs);
        uint88 randomness = uint88(uint256(keccak256(abi.encode("TestToken1"))));
        bytes32 _salt = bytes32(uint256(uint160(tokendeployer) + randomness));
        // console.log("_salt: ", _salt);
        bytes32 computedSalt = keccak256(abi.encode(_salt));
        address computedAddress = createXDeployer.computeCreate3Address(computedSalt);
        if (address(computedAddress).code.length == 0) {
            computedAddress = createXDeployer.deployCreate3(_salt, bytecode);
            console.log(string(abi.encodePacked("deployed to:")), address(computedAddress));
        } else {
            console.log(string(abi.encodePacked("already deployed at:")), address(computedAddress));
        }

        TestOFT _token = TestOFT(computedAddress);
        console.log("owner/core: ", _token.owner());
        _token.setOperator(deployer,true);

        _token.faucet(1_000 * 1e18);
        
        ILayerZeroEndpointV2 endpoint = ILayerZeroEndpointV2(0x1a44076050125825900e736c501f859c50fE728c);
        // _token.setPeer(1, addressToBytes32(address(_token)));
        _token.setPeer(252, addressToBytes32(address(_token)));

        console.log("======================================");
        console.log("    Contracts     ");
        console.log("======================================");
        console.log("testToken: ", computedAddress);
        console.log("======================================");
        console.log("balance of token: ", _token.balanceOf(deployer));
    }
}