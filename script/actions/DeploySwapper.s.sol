// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "src/Constants.sol" as Constants;
import { TenderlyHelper } from "script/utils/TenderlyHelper.sol";
import { ICurveExchange } from "src/interfaces/ICurveExchange.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Swapper } from "src/protocol/Swapper.sol";
import { ResupplyRegistry } from "src/protocol/ResupplyRegistry.sol";

contract DeploySwapper is TenderlyHelper {

    address public dev = address(0xc4ad);
    address public stablecoin;
    address public crvusdAmm;
    address public fraxAmm;
    address public core;
    Swapper public defaultSwapper;
    ResupplyRegistry public registry;

    constructor() {
        // Read addresses from deployments.json file
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/data/deployments.json");
        string memory json = vm.readFile(path);
        stablecoin = abi.decode(vm.parseJson(json, ".STABLECOIN"), (address));
        crvusdAmm = abi.decode(vm.parseJson(json, ".CURVE_POOL_REUSD_SCRVUSD"), (address));
        fraxAmm = abi.decode(vm.parseJson(json, ".CURVE_POOL_REUSD_SFRXUSD"), (address));
        registry = ResupplyRegistry(abi.decode(vm.parseJson(json, ".RESUPPLY_REGISTRY"), (address)));
        core = abi.decode(vm.parseJson(json, ".CORE"), (address));
    }

    function run() public {
        vm.startBroadcast(core);
        deploySwapper();
        vm.stopBroadcast();
    }

    function deploySwapper() public {
        //deploy swapper
        defaultSwapper = new Swapper(address(core));

        Swapper.SwapInfo memory swapinfo;

        //reusd to scrvusd
        swapinfo.swappool = crvusdAmm;
        swapinfo.tokenInIndex = 0;
        swapinfo.tokenOutIndex = 1;
        swapinfo.swaptype = 1;
        defaultSwapper.addPairing(
            address(stablecoin),
            Constants.Mainnet.CURVE_SCRVUSD,
            swapinfo
        );

        //scrvusd to reusd
        swapinfo.swappool = crvusdAmm;
        swapinfo.tokenInIndex = 1;
        swapinfo.tokenOutIndex = 0;
        swapinfo.swaptype = 1;
        defaultSwapper.addPairing(
            Constants.Mainnet.CURVE_SCRVUSD,
            address(stablecoin),
            swapinfo
        );

        //scrvusd withdraw to crvusd
        swapinfo.swappool = Constants.Mainnet.CURVE_SCRVUSD;
        swapinfo.tokenInIndex = 0;
        swapinfo.tokenOutIndex = 0;
        swapinfo.swaptype = 3;
        defaultSwapper.addPairing(
            Constants.Mainnet.CURVE_SCRVUSD,
            Constants.Mainnet.CURVE_USD_ERC20,
            swapinfo
        );

        //crvusd deposit to scrvusd
        swapinfo.swappool = Constants.Mainnet.CURVE_SCRVUSD;
        swapinfo.tokenInIndex = 0;
        swapinfo.tokenOutIndex = 0;
        swapinfo.swaptype = 2;
        defaultSwapper.addPairing(
            Constants.Mainnet.CURVE_USD_ERC20,
            Constants.Mainnet.CURVE_SCRVUSD,
            swapinfo
        );

        //reusd to sfrxusd
        swapinfo.swappool = fraxAmm;
        swapinfo.tokenInIndex = 0;
        swapinfo.tokenOutIndex = 1;
        swapinfo.swaptype = 1;
        defaultSwapper.addPairing(
            address(stablecoin),
            Constants.Mainnet.SFRAX_ERC20,
            swapinfo
        );

        //sfrxusd to reusd
        swapinfo.swappool = fraxAmm;
        swapinfo.tokenInIndex = 1;
        swapinfo.tokenOutIndex = 0;
        swapinfo.swaptype = 1;
        defaultSwapper.addPairing(
            Constants.Mainnet.SFRAX_ERC20,
            address(stablecoin),
            swapinfo
        );

        //sfrxusd withdraw to frxusd
        swapinfo.swappool = Constants.Mainnet.SFRAX_ERC20;
        swapinfo.tokenInIndex = 0;
        swapinfo.tokenOutIndex = 0;
        swapinfo.swaptype = 3;
        defaultSwapper.addPairing(
            Constants.Mainnet.SFRAX_ERC20,
            Constants.Mainnet.FRAX_ERC20,
            swapinfo
        );

        //frxusd deposit to sfrxusd
        swapinfo.swappool = Constants.Mainnet.SFRAX_ERC20;
        swapinfo.tokenInIndex = 0;
        swapinfo.tokenOutIndex = 0;
        swapinfo.swaptype = 2;
        defaultSwapper.addPairing(
            Constants.Mainnet.FRAX_ERC20,
            Constants.Mainnet.SFRAX_ERC20,
            swapinfo
        );


        //set swapper to registry
        address[] memory swappers = new address[](1);
        swappers[0] = address(defaultSwapper);
        registry.setDefaultSwappers(swappers);
    }
}
