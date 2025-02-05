// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

library VestManagerInitParams {
    struct InitParams {
        uint256 maxRedeemable;
        bytes32[3] merkleRoots;
        address[4] nonUserTargets;
        uint256[8] durations;
        uint256[8] allocPercentages;
    }

    // Constants for non-user targets
    address constant FRAX_VEST_TARGET = address(0xB1748C79709f4Ba2Dd82834B8c82D4a505003f27);

    function getInitParams(
        address permaStaker1,
        address permaStaker2,
        address treasury
    ) internal pure returns (InitParams memory) {
        bytes32[3] memory merkleRoots = [
            bytes32(0x3adb010769f8a36c20d9ec03b89fe4d7f725c8ba133ce65faba53e18d13bf41f),
            bytes32(0x3adb010769f8a36c20d9ec03b89fe4d7f725c8ba133ce65faba53e18d13bf41f),
            bytes32(0) // Set later
        ];

        address[4] memory nonUserTargets = [
            permaStaker1,  // Convex
            permaStaker2,  // Yearn
            FRAX_VEST_TARGET,
            treasury
        ];

        uint256[8] memory durations = [
            uint256(5 * 365 days),  // CONVEX
            uint256(5 * 365 days),  // YEARN
            uint256(1 * 365 days),  // Frax
            uint256(5 * 365 days),  // TREASURY
            uint256(5 * 365 days),  // REDEMPTIONS
            uint256(1 * 365 days),  // AIRDROP_TEAM
            uint256(2 * 365 days),  // AIRDROP_VICTIMS
            uint256(5 * 365 days)   // AIRDROP_LOCK_PENALTY
        ];

        uint256[8] memory allocPercentages = [
            uint256(333333333333333333),  // 33.33% Convex
            uint256(166666666666666667),  // 16.67% Yearn
            uint256(8333333333333333),    // 8.33% Frax
            uint256(191666666666666667),  // 19.17% TREASURY
            uint256(250000000000000000),  // 25.00% REDEMPTIONS
            uint256(16666666666666667),   // 16.67% AIRDROP_TEAM
            uint256(33333333333333333),   // 33.33% AIRDROP_VICTIMS
            uint256(0)                    // 0% AIRDROP_LOCK_PENALTY
        ];

        return InitParams({
            maxRedeemable: 150_000_000e18,
            merkleRoots: merkleRoots,
            nonUserTargets: nonUserTargets,
            durations: durations,
            allocPercentages: allocPercentages
        });
    }
}