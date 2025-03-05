// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "src/Constants.sol" as Constants;
import { TenderlyHelper } from "script/utils/TenderlyHelper.sol";
import { ICurveExchange } from "src/interfaces/ICurveExchange.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DeployPools is TenderlyHelper {
    address public dev = address(0xc4ad);
    address public stablecoin;
    address public swapPoolsCrvUsd;
    address public swapPoolsFrxusd;
    address public scrvusd;
    address public sfrxusd;

    constructor() {
        // Read addresses from deployments.json file
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/data/deployments.json");
        string memory json = vm.readFile(path);
        stablecoin = abi.decode(vm.parseJson(json, ".STABLECOIN"), (address));

        scrvusd = Constants.Mainnet.CURVE_SCRVUSD;
        sfrxusd = Constants.Mainnet.SFRXUSD_ERC20;
    }

    function run() public {
        issueTokens();
        vm.startBroadcast(dev);
        deployCurvePools();
        provideLiquidity();
        vm.stopBroadcast();
    }

    function deployCurvePools() public{
        address[] memory coins = new address[](2);
        coins[0] = address(stablecoin);
        coins[1] = scrvusd;
        uint8[] memory assetTypes = new uint8[](2);
        assetTypes[1] = 3; //second coin is erc4626
        bytes4[] memory methods = new bytes4[](2);
        address[] memory oracles = new address[](2);
        address crvusdAmm = ICurveExchange(Constants.Mainnet.CURVE_STABLE_FACTORY).deploy_plain_pool(
            "reUSD/scrvUSD",    // name
            "reusdscrv",        // symbol
            coins,              // coins
            200,                // A
            4000000,            // fee
            50000000000,        // off peg multi
            866,                // ma exp time
            0,                  // implementation index
            assetTypes,         // asset types - normal + erc4626
            methods,            // method ids
            oracles             // oracles
        );
        swapPoolsCrvUsd = crvusdAmm;
        console.log("reUSD/scrvUSD Pool deployed at", crvusdAmm);
        coins[1] = sfrxusd;
        address frxusdAmm = ICurveExchange(Constants.Mainnet.CURVE_STABLE_FACTORY).deploy_plain_pool(
            "reUSD/sfrxUSD",    //name
            "reusdsfrx",        //symbol
            coins,              //coins
            200,                //A
            4000000,            //fee
            50000000000,        //off peg multi
            866,                //ma exp time
            0,                  //implementation index
            assetTypes,         //asset types - normal + erc4626
            methods,            //method ids
            oracles             //oracles
        );
        swapPoolsFrxusd = frxusdAmm;
        console.log("reUSD/sfrxUSD Pool deployed at", frxusdAmm);
    }

    function issueTokens() public {
        setTokenBalance(stablecoin, dev, 100_000_000e18);
        setTokenBalance(scrvusd, dev, 100_000_000e18);
        setTokenBalance(sfrxusd, dev, 100_000_000e18);
    }

    function provideLiquidity() public {
        // Approve tokens for both pools
        IERC20(stablecoin).approve(swapPoolsCrvUsd, type(uint256).max);
        IERC20(scrvusd).approve(swapPoolsCrvUsd, type(uint256).max);
        IERC20(stablecoin).approve(swapPoolsFrxusd, type(uint256).max);
        IERC20(sfrxusd).approve(swapPoolsFrxusd, type(uint256).max);

        // Add liquidity to reUSD/scrvUSD pool
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1_000_000e18;
        amounts[1] = 1_000_000e18;
        ICurveExchange(swapPoolsCrvUsd).add_liquidity(amounts, 0, dev);
        console.log("Added liquidity to reUSD/scrvUSD pool");

        // Add liquidity to reUSD/sfrxUSD pool
        ICurveExchange(swapPoolsFrxusd).add_liquidity(amounts, 0, dev);
        console.log("Added liquidity to reUSD/sfrxUSD pool");
    }
}