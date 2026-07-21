// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "src/interfaces/IERC4626.sol";
import { IOracle } from "src/interfaces/IOracle.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IResupplyPairDeployer } from "src/interfaces/IResupplyPairDeployer.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { Mainnet, Protocol } from "src/Constants.sol";

interface ICurveLendV2Vault is IERC4626 {
    function collateral_token() external view returns (address);
}

contract LlamaLendV2CompatibilityTest is Test {
    uint256 internal constant FORK_BLOCK = 25_583_871;
    address internal constant SDOLA_V2_VAULT = 0x2b5a321C3cb1F33e1ABECD047C2649D0b4C47eBa;
    address internal constant SFRXUSD_V2_VAULT = 0x3Da0F110079012387F47C6Fc6e878F10262E300a;

    IResupplyPairDeployer internal constant DEPLOYER = IResupplyPairDeployer(Protocol.PAIR_DEPLOYER_V2);
    IResupplyRegistry internal constant REGISTRY = IResupplyRegistry(Protocol.REGISTRY);

    function setUp() public {
        vm.createSelectFork("http://wavey:8545", FORK_BLOCK);
    }

    function test_liveV2VaultsSupportFullResupplyRoundTrip() public {
        _exerciseVault(SDOLA_V2_VAULT);
        _exerciseVault(SFRXUSD_V2_VAULT);
    }

    function _exerciseVault(address vault) internal {
        (address borrowToken, address collateralToken) = DEPLOYER.getBorrowAndCollateralTokens(0, vault);
        assertEq(borrowToken, Mainnet.CRVUSD_ERC20);
        assertEq(collateralToken, ICurveLendV2Vault(vault).collateral_token());
        assertEq(IERC4626(vault).decimals(), 18);
        assertEq(IERC4626(vault).asset(), Mainnet.CRVUSD_ERC20);
        assertEq(IERC4626(vault).convertToAssets(1e18), IOracle(Protocol.BASIC_VAULT_ORACLE).getPrices(vault));

        vm.prank(Protocol.DEPLOYER);
        IResupplyPair pair = IResupplyPair(DEPLOYER.deployWithDefaultConfig(0, vault, address(0), 0));

        assertEq(pair.collateral(), vault);
        assertEq(pair.underlying(), Mainnet.CRVUSD_ERC20);
        assertEq(pair.convexBooster(), address(0));
        assertEq(pair.convexPid(), 0);

        vm.prank(Protocol.CORE);
        REGISTRY.addPair(address(pair));

        address user = address(uint160(uint256(keccak256(abi.encode(vault)))));
        deal(Mainnet.CRVUSD_ERC20, user, 5000e18);

        vm.startPrank(user);
        IERC20(Mainnet.CRVUSD_ERC20).approve(address(pair), type(uint256).max);
        pair.addCollateral(2000e18, user);
        uint256 collateralShares = pair.userCollateralBalance(user);
        assertGt(collateralShares, 0);
        assertEq(pair.totalCollateral(), collateralShares);

        uint256 borrowShares = pair.borrow(1000e18, 0, user);
        assertGt(borrowShares, 0);
        assertEq(IERC20(Protocol.STABLECOIN).balanceOf(user), 1000e18);

        vm.warp(block.timestamp + 1 days);
        pair.addInterest(false);
        (uint64 lastTimestamp,, uint128 lastShares) = pair.currentRateInfo();
        assertEq(lastTimestamp, block.timestamp);
        assertGt(lastShares, 0);

        deal(Protocol.STABLECOIN, user, 2000e18);
        IERC20(Protocol.STABLECOIN).approve(address(pair), type(uint256).max);
        pair.repay(borrowShares, user);
        pair.removeCollateral(collateralShares, user);
        vm.stopPrank();

        assertEq(pair.userBorrowShares(user), 0);
        assertEq(pair.userCollateralBalance(user), 0);
        assertEq(pair.totalCollateral(), 0);
        assertGe(IERC20(Mainnet.CRVUSD_ERC20).balanceOf(user), 4999e18);
    }
}
