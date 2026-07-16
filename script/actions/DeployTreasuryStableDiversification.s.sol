// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { TreasuryStableDiversification } from "src/dao/TreasuryStableDiversification.sol";

contract DeployTreasuryStableDiversification is Script {
    address public constant TREASURY = 0x6508eF65b0Bd57eaBD0f1D52685A70433B2d290B;
    address public constant CONVEX_DEPLOYER = 0x947B7742C403f20e5FaCcDAc5E092C943E7D0277;
    address public constant CURVE_OWNERSHIP = 0x40907540d8a6C65c637785e8f8B742ae6b0b9968;

    address public constant CRVUSD = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
    address public constant SCRVUSD = 0x0655977FEb2f289A4aB78af67BAB0d17aAb84367;
    address public constant SDOLA = 0xb45ad160634c528Cc3D2926d9807104FA3157305;
    address public constant SDOLA_SCRVUSD_POOL = 0x76A962BA6770068bCF454D34dDE17175611e6637;
    address public constant FRXUSD = 0xCAcd6fd266aF91b8AeD52aCCc382b4e165586E29;
    address public constant SFRXUSD = 0xcf62F905562626CfcDD2261162a51fd02Fc9c5b6;
    address public constant CRVUSD_FRXUSD_POOL = 0x13e12BB0E6A2f1A3d6901a59a9d585e89A6243e1;
    address public constant FRXUSD_SFRXUSD_POOL = 0xF292eB6c5dcb693Eaaf392D0562a01C3710E5978;

    uint16 public constant MAX_DEVIATION_BPS = 4;
    uint16 public constant PRICE_GUARD_DEVIATION_BPS = 4;
    uint16 public constant EXECUTION_BUFFER_BPS = 4;
    uint256 public constant MAX_PRICE = 1.001e18;

    function run() external returns (TreasuryStableDiversification diversifier) {
        vm.startBroadcast();

        diversifier = new TreasuryStableDiversification(
            CONVEX_DEPLOYER,
            TREASURY,
            CRVUSD,
            MAX_DEVIATION_BPS
        );
        diversifier.setTargets(buildTargets());
        diversifier.transferOwnership(CURVE_OWNERSHIP);

        vm.stopBroadcast();

        console.log("TreasuryStableDiversification deployed at", address(diversifier));
        console.log("TreasuryStableDiversification owner", diversifier.owner());
        console.log("TreasuryStableDiversification pending owner", diversifier.pendingOwner());
        console.log("TreasuryStableDiversification treasury", diversifier.treasury());
    }

    function buildTargets() public pure returns (TreasuryStableDiversification.Target[] memory targets) {
        targets = new TreasuryStableDiversification.Target[](3);
        targets[0] = TreasuryStableDiversification.Target({
            token: SDOLA,
            weight: 25,
            swapPool: SDOLA_SCRVUSD_POOL,
            vault: address(0),
            inputToken: address(0),
            stakedAsset: SCRVUSD,
            maxPrice: 0,
            maxSpotEmaDeviationBps: 0,
            executionBufferBps: 0
        });
        targets[1] = TreasuryStableDiversification.Target({
            token: FRXUSD,
            weight: 75,
            swapPool: CRVUSD_FRXUSD_POOL,
            vault: address(0),
            inputToken: address(0),
            stakedAsset: address(0),
            maxPrice: MAX_PRICE,
            maxSpotEmaDeviationBps: PRICE_GUARD_DEVIATION_BPS,
            executionBufferBps: EXECUTION_BUFFER_BPS
        });
        targets[2] = TreasuryStableDiversification.Target({
            token: SFRXUSD,
            weight: 0,
            swapPool: FRXUSD_SFRXUSD_POOL,
            vault: address(0),
            inputToken: FRXUSD,
            stakedAsset: address(0),
            maxPrice: MAX_PRICE,
            maxSpotEmaDeviationBps: PRICE_GUARD_DEVIATION_BPS,
            executionBufferBps: EXECUTION_BUFFER_BPS
        });
    }
}
