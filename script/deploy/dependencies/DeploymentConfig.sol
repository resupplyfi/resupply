// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "src/Constants.sol" as Constants;

library DeploymentConfig {
    address constant DEPLOYER = 0xFE11a5009f2121622271e7dd0FD470264e076af6;
    address constant FRAX_VEST_TARGET = 0xB1748C79709f4Ba2Dd82834B8c82D4a505003f27;
    address constant PRISMA_TOKENS_BURN_ADDRESS = address(0xdead);
    uint256 constant EPOCH_LENGTH = 1 weeks;
    uint24 constant STAKER_COOLDOWN_EPOCHS = 2;

    // Token configuration
    uint256 constant GOV_TOKEN_INITIAL_SUPPLY = 60_000_000e18;
    string constant GOV_TOKEN_NAME = "Resupply";
    string constant GOV_TOKEN_SYMBOL = "RSUP";

    // PermaStaker
    string constant PERMA_STAKER_CONVEX_NAME = "Resupply PermaStaker: Convex";
    string constant PERMA_STAKER_YEARN_NAME = "Resupply PermaStaker: Yearn";
    address constant PERMA_STAKER_CONVEX_OWNER = 0xa3C5A1e09150B75ff251c1a7815A07182c3de2FB;
    address constant PERMA_STAKER_YEARN_OWNER = 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52;

    // Emissions weights (1e4 precision)
    uint256 constant INITIAL_EMISSIONS_WEIGHT_DEBT = 2500;
    uint256 constant INITIAL_EMISSIONS_WEIGHT_INSURANCE_POOL = 2500;
    uint256 constant INITIAL_EMISSIONS_WEIGHT_LP = 5000;

    // Voter configuration (1e4 precision)
    uint256 constant VOTER_MIN_CREATE_PROPOSAL_PCT = 100;
    uint256 constant VOTER_QUORUM_PCT = 3000;

    // Emissions controller configuration (rates are 1e18 precision)
    uint256 constant EMISSIONS_SCHEDULE_YEAR_1 = 183143319640535100;
    uint256 constant EMISSIONS_SCHEDULE_YEAR_2 = 130573632743654969;
    uint256 constant EMISSIONS_SCHEDULE_YEAR_3 = 93429770042296321;
    uint256 constant EMISSIONS_SCHEDULE_YEAR_4 = 64756001614012807;
    uint256 constant EMISSIONS_SCHEDULE_YEAR_5 = 40950214498301975;
    uint256 constant EMISSIONS_CONTROLLER_TAIL_RATE = 19860811573103551;
    uint256 constant EMISSIONS_CONTROLLER_EPOCHS_PER = 52;
    uint256 constant EMISSIONS_CONTROLLER_BOOTSTRAP_EPOCHS = 0;

    // Configs: Protocol
    uint256 constant DEFAULT_BORROW_LIMIT = 0;
    uint256 constant DEFAULT_MAX_LTV = 95_000; // 1e5 precision
    uint256 constant DEFAULT_LIQ_FEE = 5_000;  // 1e5 precision
    uint256 constant DEFAULT_MINT_FEE = 0;     // 1e5 precision
    uint256 constant DEFAULT_PROTOCOL_REDEMPTION_FEE = 1e18 / 2; // portion of fee for stakers (1e18 precision)
    uint256 constant FEE_SPLIT_IP = 2500;      // 1e4 precision
    uint256 constant FEE_SPLIT_TREASURY = 500; // 1e4 precision
    uint256 constant FEE_SPLIT_STAKERS = 7000; // 1e4 precision

    // Tokens
    address constant SCRVUSD = Constants.Mainnet.CURVE_SCRVUSD;
    address constant SFRXUSD = Constants.Mainnet.SFRXUSD_ERC20;
    address constant CURVE_STABLE_FACTORY = Constants.Mainnet.CURVE_STABLE_FACTORY;

    // SafeHelper
    uint256 constant MAX_GAS_PER_BATCH = 15_000_000;
}

library CreateX {
    address internal constant CREATEX_DEPLOYER = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;
    // Salts
    bytes32 internal constant SALT_GOV_TOKEN = 0xfe11a5009f2121622271e7dd0fd470264e076af6007817270164e1790196c4f0; // 0x419905
    bytes32 internal constant SALT_STABLECOIN = 0xfe11a5009f2121622271e7dd0fd470264e076af6007d4a011e1aea8d0220315d; // 0x57ab1e
    bytes32 internal constant SALT_CORE = 0xfe11a5009f2121622271e7dd0fd470264e076af60075182fe1eff89e02ce3cff; // 0xc07e0000
    bytes32 internal constant SALT_REGISTRY = 0xfe11a5009f2121622271e7dd0fd470264e076af60035199030be4b0602635825; // 0x1010101
    bytes32 internal constant SALT_INSURANCE_POOL = 0xfe11a5009f2121622271e7dd0fd470264e076af600bd0b20142b743201bee438; // 0x000000
    bytes32 internal constant SALT_VOTER = 0xfe11a5009f2121622271e7dd0fd470264e076af60005f722dce9505702447be8; // 0x11111
    bytes32 internal constant SALT_GOV_STAKER = 0xfe11a5009f2121622271e7dd0fd470264e076af600ac101fb2686a8c0015ef91; // 0x22222
    bytes32 internal constant SALT_EMISSIONS_CONTROLLER = 0xfe11a5009f2121622271e7dd0fd470264e076af60045a2b62cd5fec002054177; // 0x3333
    bytes32 internal constant SALT_TREASURY = 0xfe11a5009f2121622271e7dd0fd470264e076af6003e18f2a15963dc02ebe90a; // 0x44444
    bytes32 internal constant SALT_PAIR_DEPLOYER = 0xfe11a5009f2121622271e7dd0fd470264e076af6005ae1044d7cd9aa0200df43; // 0x55555
    bytes32 internal constant SALT_VEST_MANAGER = 0xfe11a5009f2121622271e7dd0fd470264e076af6000cc7db37bf283f00158d19; // 0x66666
    bytes32 internal constant SALT_INTEREST_RATE_CALCULATOR = 0xfe11a5009f2121622271e7dd0fd470264e076af6005763a7460bd2b7038a032e; // 0x77777
    bytes32 internal constant SALT_LIQUIDATION_HANDLER = 0xfe11a5009f2121622271e7dd0fd470264e076af600574340f6003cec01964db0; // 0x88888
    bytes32 internal constant SALT_REDEMPTION_HANDLER = 0xfe11a5009f2121622271e7dd0fd470264e076af6002dd74d21d97b27032aca93; // 0x99999
    bytes32 internal constant SALT_PERMA_STAKER_CONVEX = 0xfe11a5009f2121622271e7dd0fd470264e076af600847421d8997e1100819f27; // 0xCCCCC
    bytes32 internal constant SALT_PERMA_STAKER_YEARN = 0xfe11a5009f2121622271e7dd0fd470264e076af6005045c04e56a6ce00770772; // 0x12341234
    bytes32 internal constant SALT_TREASURY_MANAGER = 0xfe11a5009f2121622271e7dd0fd470264e076af6004743fa1885004c02ae2b7e; // 0x095000
    bytes32 internal constant SALT_GUARDIAN = 0xfe11a5009f2121622271e7dd0fd470264e076af6001380bed7c94ead020a25f8; // 0x095000
}
