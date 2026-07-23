// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "src/interfaces/IERC4626.sol";
import { IOracle } from "src/interfaces/IOracle.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IResupplyPairDeployer } from "src/interfaces/IResupplyPairDeployer.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IConvexStaking } from "src/interfaces/convex/IConvexStaking.sol";
import { Mainnet, Protocol } from "src/Constants.sol";

interface ICurveLendV2Vault is IERC4626 {
    function collateral_token() external view returns (address);
}

/// @notice Fixed-block regression for the boundary between live LlamaLend v2
/// lender vaults and Resupply. The proposal test covers governance calldata;
/// this test independently covers vault discovery, pricing, and user flows.
contract LlamaLendV2CompatibilityTest is Test {
    uint256 internal constant FORK_BLOCK = 25_583_871;
    address internal constant SDOLA_V2_VAULT = 0x2b5a321C3cb1F33e1ABECD047C2649D0b4C47eBa;
    address internal constant SFRXUSD_V2_VAULT = 0x3Da0F110079012387F47C6Fc6e878F10262E300a;
    uint256 internal constant SDOLA_CONVEX_PID = 570;
    uint256 internal constant SFRXUSD_CONVEX_PID = 571;

    IResupplyPairDeployer internal constant DEPLOYER = IResupplyPairDeployer(Protocol.PAIR_DEPLOYER_V2);
    IResupplyRegistry internal constant REGISTRY = IResupplyRegistry(Protocol.REGISTRY);

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_URL"), FORK_BLOCK);

        // Production adds this metadata in the governance proposal before
        // deploying either pair. Add it here so this standalone compatibility
        // test exercises the same protocol ID and selectors.
        vm.prank(Protocol.CORE);
        DEPLOYER.addSupportedProtocol("CurveLendV2", 1e18, 1e20, bytes4(keccak256("asset()")), bytes4(keccak256("collateral_token()")));
    }

    function test_liveV2VaultsSupportFullResupplyRoundTrip() public {
        _exerciseVault(SDOLA_V2_VAULT, SDOLA_CONVEX_PID);
        _exerciseVault(SFRXUSD_V2_VAULT, SFRXUSD_CONVEX_PID);
    }

    function _exerciseVault(address vault, uint256 convexPid) internal {
        // Resupply discovers a Curve market from the vault's asset and
        // collateral selectors. These assertions guard the LLv2 ABI boundary
        // and the share-to-asset price consumed by BasicVaultOracle.
        (address borrowToken, address collateralToken) = DEPLOYER.getBorrowAndCollateralTokens(Protocol.PROTOCOL_ID_CURVE_V2, vault);
        assertEq(borrowToken, Mainnet.CRVUSD_ERC20);
        assertEq(collateralToken, ICurveLendV2Vault(vault).collateral_token());
        assertEq(IERC4626(vault).decimals(), 18);
        assertEq(IERC4626(vault).asset(), Mainnet.CRVUSD_ERC20);
        assertEq(IERC4626(vault).convertToAssets(1e18), IOracle(Protocol.BASIC_VAULT_ORACLE).getPrices(vault));

        // Convex registers the lender vault itself as the pool LP token. This
        // check prevents accidentally staking the pair's collateral in a pool
        // for a different vault.
        (address lpToken,,, address rewards,, bool shutdown) = IConvexStaking(Mainnet.CONVEX_BOOSTER).poolInfo(convexPid);
        assertEq(lpToken, vault);
        assertFalse(shutdown);

        vm.prank(Protocol.DEPLOYER);
        IResupplyPair pair = IResupplyPair(DEPLOYER.deployWithDefaultConfig(Protocol.PROTOCOL_ID_CURVE_V2, vault, Mainnet.CONVEX_BOOSTER, convexPid));

        assertEq(pair.collateral(), vault);
        assertEq(pair.underlying(), Mainnet.CRVUSD_ERC20);
        assertEq(pair.convexBooster(), Mainnet.CONVEX_BOOSTER);
        assertEq(pair.convexPid(), convexPid);

        // Registration is part of the compatibility boundary because only a
        // registered pair may mint reUSD during the borrow below.
        vm.prank(Protocol.CORE);
        REGISTRY.addPair(address(pair));

        // Exercise the full path used by a Resupply borrower: crvUSD enters
        // the LLv2 ERC-4626 vault, its shares become pair collateral, and the
        // user borrows reUSD against those shares.
        address user = address(uint160(uint256(keccak256(abi.encode(vault)))));
        deal(Mainnet.CRVUSD_ERC20, user, 5000e18);

        vm.startPrank(user);
        IERC20(Mainnet.CRVUSD_ERC20).approve(address(pair), type(uint256).max);
        pair.addCollateral(2000e18, user);
        uint256 collateralShares = pair.userCollateralBalance(user);
        assertGt(collateralShares, 0);
        assertEq(pair.totalCollateral(), collateralShares);
        assertEq(IConvexStaking(rewards).balanceOf(address(pair)), collateralShares);
        assertEq(IERC20(vault).balanceOf(address(pair)), 0);

        uint256 borrowShares = pair.borrow(1000e18, 0, user);
        assertGt(borrowShares, 0);
        assertEq(IERC20(Protocol.STABLECOIN).balanceOf(user), 1000e18);

        // Accruing after a time jump proves the pair's rate calculator can
        // consume the LLv2 vault accounting, not just complete a same-block
        // deposit and withdrawal.
        vm.warp(block.timestamp + 1 days);
        pair.addInterest(false);
        (uint64 lastTimestamp,, uint128 lastShares) = pair.currentRateInfo();
        assertEq(lastTimestamp, block.timestamp);
        assertGt(lastShares, 0);

        // Supply extra reUSD to cover the interest accrued after the borrow.
        deal(Protocol.STABLECOIN, user, 2000e18);
        IERC20(Protocol.STABLECOIN).approve(address(pair), type(uint256).max);
        pair.repay(borrowShares, user);
        pair.removeCollateral(collateralShares, user);
        vm.stopPrank();

        assertEq(pair.userBorrowShares(user), 0);
        assertEq(pair.userCollateralBalance(user), 0);
        assertEq(pair.totalCollateral(), 0);
        assertEq(IConvexStaking(rewards).balanceOf(address(pair)), 0);
        assertGe(IERC20(Mainnet.CRVUSD_ERC20).balanceOf(user), 4999e18);
    }
}
