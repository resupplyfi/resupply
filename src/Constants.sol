// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase } from "forge-std/Test.sol";

library Mainnet {
    uint256 internal constant CHAIN_ID = 1;
    
    address internal constant CORE = address(0);
    address internal constant STABLE_TOKEN = address(0);
    address internal constant CONVEX_DEPLOYER = 0x947B7742C403f20e5FaCcDAc5E092C943E7D0277;
    address internal constant CONVEX_BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
    address internal constant CRV_ERC20 = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address internal constant CVX_ERC20 = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address internal constant FRXUSD_ERC20 = 0xCAcd6fd266aF91b8AeD52aCCc382b4e165586E29;
    address internal constant SFRXUSD_ERC20 = 0xcf62F905562626CfcDD2261162a51fd02Fc9c5b6;
    address internal constant CURVE_USD_ERC20 = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
    address internal constant CURVE_SCRVUSD = 0x0655977FEb2f289A4aB78af67BAB0d17aAb84367;
    address internal constant CURVE_STABLE_FACTORY = 0x6A8cbed756804B16E05E741eDaBd5cB544AE21bf;

    //fraxlend
    address internal constant FRAXLEND_SFRXETH_FRXUSD = 0xaB3cb84c310186B2Fa4B4503624A5D90b5DcB22D;
    address internal constant FRAXLEND_SUSDE_FRXUSD = 0x28Cdf6Ce79702AAeFbF217cF98cbD11f5639B9f1;
    address internal constant FRAXLEND_WBTC_FRXUSD = 0x37110563E3856D413B821f07C7E3991c4493673D;
    address internal constant FRAXLEND_SCRVUSD_FRXUSD = 0x8087346b8865e5B0bF9F8A49742c2D83f6a50a6c;

    //curvelend
    address internal constant CURVELEND_SDOLA_CRVUSD = 0x14361C243174794E2207296a6AD59bb0Dec1d388;
    address internal constant CURVELEND_SUSDE_CRVUSD = 0x4a7999c55d3a93dAf72EA112985e57c2E3b9e95D;
    address internal constant CURVELEND_USDE_CRVUSD = 0xc687141c18F20f7Ba405e45328825579fDdD3195;
    address internal constant CURVELEND_TBTC_CRVUSD = 0xb2b23C87a4B6d1b03Ba603F7C3EB9A81fDC0AAC9;
    address internal constant CURVELEND_WBTC_CRVUSD = 0xccd37EB6374Ae5b1f0b85ac97eFf14770e0D0063;
    address internal constant CURVELEND_WETH_CRVUSD = 0x8fb1c7AEDcbBc1222325C39dd5c1D2d23420CAe3;
    address internal constant CURVELEND_WSTETH_CRVUSD = 0x21CF1c5Dc48C603b89907FE6a7AE83EA5e3709aF;
    address internal constant CURVELEND_YNETH_CRVUSD = 0x52036c9046247C3358c987A2389FFDe6Ef8564c9;
    address internal constant CURVELEND_SFRXUSD_CRVUSD = 0x8E3009b59200668e1efda0a2F2Ac42b24baa2982;
    uint256 internal constant CURVELEND_SDOLA_CRVUSD_ID = 384;
    uint256 internal constant CURVELEND_SUSDE_CRVUSD_ID = 361;
    uint256 internal constant CURVELEND_USDE_CRVUSD_ID = 371;
    uint256 internal constant CURVELEND_TBTC_CRVUSD_ID = 328;
    uint256 internal constant CURVELEND_WBTC_CRVUSD_ID = 344;
    uint256 internal constant CURVELEND_WETH_CRVUSD_ID = 365;
    uint256 internal constant CURVELEND_WSTETH_CRVUSD_ID = 364;
    uint256 internal constant CURVELEND_YNETH_CRVUSD_ID = 415;
    uint256 internal constant CURVELEND_SFRXUSD_CRVUSD_ID = 438;

    // LayerZero
    address internal constant LAYERZERO_ENDPOINTV2 = 0x1a44076050125825900e736c501f859c50fE728c;
}

library Sepolia {
    uint256 internal constant CHAIN_ID = 11155111;
    address internal constant LAYERZERO_ENDPOINTV2 = 0x6EDCE65403992e310A62460808c4b910D972f10f;
}

library CreateX {
    address internal constant CREATEX_DEPLOYER = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;
    // Salts
    bytes32 internal constant SALT_GOV_TOKEN = 0xfe11a5009f2121622271e7dd0fd470264e076af6007817270164e1790196c4f0; // 0x419905
    bytes32 internal constant SALT_STABLECOIN = 0xfe11a5009f2121622271e7dd0fd470264e076af6007d4a011e1aea8d0220315d; // 0x57ab1e
    bytes32 internal constant SALT_CORE = 0xfe11a5009f2121622271e7dd0fd470264e076af60075182fe1eff89e02ce3cff; // 0xc07e0000
    bytes32 internal constant SALT_REGISTRY = 0xfe11a5009f2121622271e7dd0fd470264e076af60035199030be4b0602635825; // 0x1010101
    bytes32 internal constant SALT_INSURANCE_POOL = 0xfe11a5009f2121622271e7dd0fd470264e076af600bd0b20142b743201bee438; // 0x000000
    bytes32 internal constant SALT_VOTER = 0xfe11a5009f2121622271e7dd0fd470264e076af60067a2e41ad02c1700e3f506; // 0x11111
    bytes32 internal constant SALT_GOV_STAKER = 0xfe11a5009f2121622271e7dd0fd470264e076af600ac101fb2686a8c0015ef91; // 0x22222
    bytes32 internal constant SALT_EMISSIONS_CONTROLLER = 0xfe11a5009f2121622271e7dd0fd470264e076af60045a2b62cd5fec002054177; // 0x3333
    bytes32 internal constant SALT_TREASURY = 0xfe11a5009f2121622271e7dd0fd470264e076af6006bbac7a598ad55036e9c9c; // 0x44444
    bytes32 internal constant SALT_PAIR_DEPLOYER = 0xfe11a5009f2121622271e7dd0fd470264e076af6005ae1044d7cd9aa0200df43; // 0x55555
    bytes32 internal constant SALT_VEST_MANAGER = 0xfe11a5009f2121622271e7dd0fd470264e076af6000cc7db37bf283f00158d19; // 0x66666
    bytes32 internal constant SALT_INTEREST_RATE_CALCULATOR = 0xfe11a5009f2121622271e7dd0fd470264e076af6005763a7460bd2b7038a032e; // 0x77777
    bytes32 internal constant SALT_LIQUIDATION_HANDLER = 0xfe11a5009f2121622271e7dd0fd470264e076af600574340f6003cec01964db0; // 0x88888
    bytes32 internal constant SALT_REDEMPTION_HANDLER = 0xfe11a5009f2121622271e7dd0fd470264e076af6002dd74d21d97b27032aca93; // 0x99999
    bytes32 internal constant SALT_PERMA_STAKER_CONVEX = 0xfe11a5009f2121622271e7dd0fd470264e076af600847421d8997e1100819f27; // 0xCCCCC
    bytes32 internal constant SALT_PERMA_STAKER_YEARN = 0xfe11a5009f2121622271e7dd0fd470264e076af6005045c04e56a6ce00770772; // 0x12341234
}

abstract contract Helper is TestBase {
    constructor() {
        labelConstants();
    }

    function labelConstants() public {
        vm.label(0x947B7742C403f20e5FaCcDAc5E092C943E7D0277, "Constants.CONVEX_DEPLOYER");
        vm.label(0xF403C135812408BFbE8713b5A23a04b3D48AAE31, "Constants.CONVEX_BOOSTER");
        vm.label(0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0, "Constants.FXS_ERC20");
        vm.label(0x5E8422345238F34275888049021821E8E08CAa1f, "Constants.FRXETH_ERC20");
        vm.label(0xac3E018457B222d93114458476f3E3416Abbe38F, "Constants.SFRXETH_ERC20");
        vm.label(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, "Constants.WETH_ERC20");
        vm.label(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599, "Constants.WBTC_ERC20");
        vm.label(0xD533a949740bb3306d119CC777fa900bA034cd52, "Constants.CRV_ERC20");
        vm.label(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B, "Constants.CVX_ERC20");
        vm.label(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, "Constants.USDC_ERC20");
        vm.label(0xCAcd6fd266aF91b8AeD52aCCc382b4e165586E29, "Constants.FRXUSD_ERC20");
        vm.label(0xcf62F905562626CfcDD2261162a51fd02Fc9c5b6, "Constants.SFRXUSD_ERC20");
        vm.label(0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E, "Constants.CURVE_USD_ERC20");
        vm.label(0x0655977FEb2f289A4aB78af67BAB0d17aAb84367, "Constants.CURVE_SCRVUSD");
        vm.label(0x6A8cbed756804B16E05E741eDaBd5cB544AE21bf, "Constants.CURVE_STABLE_FACTORY");
    }
}

library Fraxtal {
    uint256 internal constant CHAIN_ID = 252;

    address internal constant WFRXETH_ERC20 = 0xFC00000000000000000000000000000000000006;
    address internal constant SFRXETH_ERC20 = 0xFC00000000000000000000000000000000000005;
    address internal constant FPIS_ERC20 = 0xfc00000000000000000000000000000000000004;
    address internal constant FPI_ERC20 = 0xFc00000000000000000000000000000000000003;
    address internal constant FXS_ERC20 = 0xFc00000000000000000000000000000000000002;
    address internal constant FRXUSD_ERC20 = 0xFc00000000000000000000000000000000000001;
    address internal constant SFRXUSD_ERC20 = 0xfc00000000000000000000000000000000000008;
    address internal constant FRXBTC_ERC20 = 0xfC00000000000000000000000000000000000007;

    // LayerZero
    address internal constant LAYERZERO_ENDPOINTV2 = 0x1a44076050125825900e736c501f859c50fE728c;
}