pragma solidity 0.8.28;

import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { Protocol } from "src/Constants.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { console } from "forge-std/console.sol";

contract Verify is BaseAction {
    address public constant deployer = Protocol.DEPLOYER;
    // Defaults
    address public constant oracle = 0xcb7E25fbbd8aFE4ce73D7Dac647dbC3D847F3c82;
    address public constant rateCalculator = 0x77777777729C405efB6Ac823493e6111F0070D67;
    uint256 public constant maxLTV = 95_000;
    uint256 public constant liquidationFee = 5_000;
    uint256 public constant mintFee = 0;
    uint256 public constant protocolRedemptionFee = 5 * 10 ** 17;
    address public constant registry = 0x10101010E0C3171D894B71B3400668aF311e7D94;
    address public constant convexBooster = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
    address public constant govToken = Protocol.GOV_TOKEN;
    
    function run() public {
        address pair = 0xF4A6113FbD71Ac1825751A6fe844A156f60C83EF;
        address collateral = 0xdfA525BD3A8e59d336EF725309F855250538c337;
        string memory name = IResupplyPair(pair).name();
        console.log("Name:", name);
        uint256 stakingId = 458;
        uint256 borrowLimit = 10_000_000e18;

        (bytes memory configData, bytes memory immutables, bytes memory customConfigData) = computeConstructorArgs(collateral, name, stakingId, borrowLimit);
        
        console.log('core');
        console.log(core);
        console.log('configData');
        console.logBytes(configData);
        console.log('immutables');
        console.logBytes(immutables);
        console.log('customConfigData');
        console.logBytes(customConfigData);

        bytes memory constructorData = abi.encode(Protocol.CORE, configData, immutables, customConfigData);
        console.log('constructorData');
        console.logBytes(constructorData);

    }

    function computeConstructorArgs(address collateral, string memory name, uint256 stakingId, uint256 borrowLimit) public view returns (bytes memory configData, bytes memory immutables, bytes memory customConfigData) {
        // Encode config data
        configData = abi.encode(
            collateral,
            oracle,
            rateCalculator,
            maxLTV,
            borrowLimit,
            liquidationFee,
            mintFee,
            protocolRedemptionFee
        );

        // Encode immutables
        immutables = abi.encode(registry);

        // Encode custom config data
        customConfigData = abi.encode(
            name,
            govToken,
            convexBooster,
            stakingId
        );
    }
}