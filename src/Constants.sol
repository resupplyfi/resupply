// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

// **NOTE** Generated code, do not modify.  Run 'npm run generate:constants'.

import { TestBase } from "forge-std/Test.sol";

library Mainnet {
    address internal constant CORE = address(0);
    address internal constant STABLE_TOKEN = address(0);
    address internal constant CONVEX_DEPLOYER = 0x947B7742C403f20e5FaCcDAc5E092C943E7D0277;
    address internal constant CONVEX_BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
    address internal constant FRAX_ERC20 = 0x853d955aCEf822Db058eb8505911ED77F175b99e;
    address internal constant FXS_ERC20 = 0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0;
    address internal constant FRXETH_ERC20 = 0x5E8422345238F34275888049021821E8E08CAa1f;
    address internal constant SFRXETH_ERC20 = 0xac3E018457B222d93114458476f3E3416Abbe38F;
    address internal constant WETH_ERC20 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant WBTC_ERC20 = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address internal constant CRV_ERC20 = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address internal constant CVX_ERC20 = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address internal constant USDC_ERC20 = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant SFRAX_ERC20 = 0xA663B02CF0a4b149d2aD41910CB81e23e1c41c32;
    address internal constant CURVE_USD_ERC20 = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;



    address internal constant FRAXLEND_SFRXETH_FRAX = 0x78bB3aEC3d855431bd9289fD98dA13F9ebB7ef15;
    address internal constant CURVELEND_SFRAX_CRVUSD = 0xd0c183C9339e73D7c9146D48E1111d1FBEe2D6f9;
    uint256 internal constant CURVELEND_SFRAX_CRVUSD_ID = 376;
}

abstract contract Helper is TestBase {
    constructor() {
        labelConstants();
    }

    function labelConstants() public {
        vm.label(0x947B7742C403f20e5FaCcDAc5E092C943E7D0277, "Constants.CONVEX_DEPLOYER");
        vm.label(0xF403C135812408BFbE8713b5A23a04b3D48AAE31, "Constants.CONVEX_BOOSTER");
        vm.label(0x853d955aCEf822Db058eb8505911ED77F175b99e, "Constants.FRAX_ERC20");
        vm.label(0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0, "Constants.FXS_ERC20");
        vm.label(0x5E8422345238F34275888049021821E8E08CAa1f, "Constants.FRXETH_ERC20");
        vm.label(0xac3E018457B222d93114458476f3E3416Abbe38F, "Constants.SFRXETH_ERC20");
        vm.label(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, "Constants.WETH_ERC20");
        vm.label(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599, "Constants.WBTC_ERC20");
        vm.label(0xD533a949740bb3306d119CC777fa900bA034cd52, "Constants.CRV_ERC20");
        vm.label(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B, "Constants.CVX_ERC20");
        vm.label(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, "Constants.USDC_ERC20");
        vm.label(0xA663B02CF0a4b149d2aD41910CB81e23e1c41c32, "Constants.SFRAX_ERC20");
        vm.label(0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E, "Constants.CURVE_USD_ERC20");
    }
}

library Fraxtal {
    address internal constant WFRXETH_ERC20 = 0xFC00000000000000000000000000000000000006;
    address internal constant SFRXETH_ERC20 = 0xFC00000000000000000000000000000000000005;
    address internal constant FPIS_ERC20 = 0xfc00000000000000000000000000000000000004;
    address internal constant FPI_ERC20 = 0xFc00000000000000000000000000000000000003;
    address internal constant FXS_ERC20 = 0xFc00000000000000000000000000000000000002;
    address internal constant FRAX_ERC20 = 0xFc00000000000000000000000000000000000001;
    address internal constant SFRAX_ERC20 = 0xfc00000000000000000000000000000000000008;
    address internal constant FRXBTC_ERC20 = 0xfC00000000000000000000000000000000000007;
}
