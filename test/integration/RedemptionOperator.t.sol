// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Setup } from "test/integration/Setup.sol";
import { RedemptionOperator } from "src/dao/operators/RedemptionOperator.sol";
import { UpgradeOperator } from "src/dao/operators/UpgradeOperator.sol";
import { IUpgradeableOperator } from "src/interfaces/IUpgradeableOperator.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IRedemptionHandler } from "src/interfaces/IRedemptionHandler.sol";
import { IFraxLoan } from "src/interfaces/IFraxLoan.sol";
import { IAuthHook } from "src/interfaces/IAuthHook.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Upgrades } from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import { Options } from "@openzeppelin/foundry-upgrades/Options.sol";
import { Protocol, Mainnet } from "src/Constants.sol";

contract RedemptionOperatorTest is Setup {
    using SafeERC20 for IERC20;

    RedemptionOperator public redemptionOperator;
    address public bot = address(0xB0B);

    function setUp() public override {
        super.setUp();
        address[] memory initialApproved = new address[](1);
        initialApproved[0] = bot;
        bytes memory initializerData = abi.encodeCall(RedemptionOperator.initialize, initialApproved);
        Options memory options;
        options.unsafeSkipAllChecks = true;
        address proxy = Upgrades.deployUUPSProxy(
            "RedemptionOperator.sol:RedemptionOperator",
            initializerData,
            options
        );
        redemptionOperator = RedemptionOperator(proxy);
        _ensureFraxLoanWhitelist();
    }

    function test_IsProfitable_Zero() public {
        (address pair, uint256 profit, uint256 redeemAmount) = redemptionOperator.isProfitable(0);
        assertEq(pair, address(0));
        assertEq(profit, 0);
        assertEq(redeemAmount, 0);
    }

    function test_IsProfitable_RoundTrip() public {
        uint256 flashAmount = 10_000e18;
        (address pair, uint256 profit, uint256 redeemAmount) = redemptionOperator.isProfitable(flashAmount);
        if (pair == address(0) || profit == 0 || redeemAmount == 0) {
            return;
        }

        _seedPair(IResupplyPair(pair));
        uint256 maxRedeemable = IRedemptionHandler(address(redemptionHandler)).getMaxRedeemableDebt(pair);
        if (maxRedeemable == 0 || redeemAmount > maxRedeemable) {
            return;
        }

        address underlying = IResupplyPair(pair).underlying();
        address treasuryAsset = underlying;
        if (underlying == Mainnet.FRXUSD_ERC20) {
            uint256 frxAvailable = IERC20(Mainnet.FRXUSD_ERC20).balanceOf(redemptionOperator.frxUsdFlashLender());
            if (frxAvailable < flashAmount) {
                treasuryAsset = Mainnet.CRVUSD_ERC20;
            }
        }

        uint256 treasuryBefore = IERC20(treasuryAsset).balanceOf(Protocol.TREASURY);
        vm.prank(bot);
        redemptionOperator.executeRedemption(
            pair,
            flashAmount,
            redeemAmount,
            0,
            type(uint256).max
        );
        uint256 treasuryAfter = IERC20(treasuryAsset).balanceOf(Protocol.TREASURY);
        assertGt(treasuryAfter - treasuryBefore, 0, "profit not recorded");
    }

    function test_ExecuteRedemption_MinSwapTooHighReverts() public {
        address pairAddress = _findPair(Mainnet.CRVUSD_ERC20);
        require(pairAddress != address(0), "pair not found");
        IResupplyPair pair = IResupplyPair(pairAddress);
        _seedPair(pair);

        vm.expectRevert();
        vm.prank(bot);
        redemptionOperator.executeRedemption(
            pairAddress,
            1_000e18,
            type(uint256).max,
            0,
            type(uint256).max
        );
    }

    function test_UpgradeOperator_CanUpgradeRedemptionOperator() public {
        UpgradeOperator upgradeOperator = new UpgradeOperator(Protocol.CORE, Protocol.DEPLOYER);
        Options memory options;
        options.unsafeSkipAllChecks = true;
        address newImplementation = Upgrades.prepareUpgrade("RedemptionOperator.sol:RedemptionOperator", options);

        vm.prank(address(core));
        core.setOperatorPermissions(
            address(upgradeOperator),
            address(redemptionOperator),
            IUpgradeableOperator.upgradeToAndCall.selector,
            true,
            IAuthHook(address(0))
        );

        address implBefore = Upgrades.getImplementationAddress(address(redemptionOperator));
        vm.prank(Protocol.DEPLOYER);
        upgradeOperator.upgradeToAndCall(address(redemptionOperator), newImplementation, "");
        address implAfter = Upgrades.getImplementationAddress(address(redemptionOperator));

        assertNotEq(implAfter, implBefore);
        assertEq(implAfter, newImplementation);
    }

    function test_UpgradeOperator_RequiresCorePermission() public {
        UpgradeOperator upgradeOperator = new UpgradeOperator(Protocol.CORE, Protocol.DEPLOYER);
        Options memory options;
        options.unsafeSkipAllChecks = true;
        address newImplementation = Upgrades.prepareUpgrade("RedemptionOperator.sol:RedemptionOperator", options);

        vm.prank(Protocol.DEPLOYER);
        vm.expectRevert("!authorized");
        upgradeOperator.upgradeToAndCall(address(redemptionOperator), newImplementation, "");
    }

    function test_UpgradeOperator_NotOwner() public {
        UpgradeOperator upgradeOperator = new UpgradeOperator(Protocol.CORE, Protocol.DEPLOYER);
        Options memory options;
        options.unsafeSkipAllChecks = true;
        address newImplementation = Upgrades.prepareUpgrade("RedemptionOperator.sol:RedemptionOperator", options);

        vm.prank(address(1));
        vm.expectRevert("!authorized");
        upgradeOperator.upgradeToAndCall(address(redemptionOperator), newImplementation, "");
    }


    function _findPair(address underlying) internal view returns (address) {
        address[] memory pairs = registry.getAllPairAddresses();
        return _findPairFromList(pairs, underlying);
    }

    function _findPairFromList(address[] memory pairs, address underlying) internal view returns (address) {
        for (uint256 i = 0; i < pairs.length; i++) {
            if (IResupplyPair(pairs[i]).underlying() == underlying) {
                return pairs[i];
            }
        }
        return address(0);
    }

    function _ensureDebt(IResupplyPair pair) internal {
        uint256 minBorrow = pair.minimumBorrowAmount();
        uint256 available = pair.totalDebtAvailable();
        if (available <= minBorrow) return;

        uint256 borrowAmount = minBorrow * 5;
        if (borrowAmount > available) borrowAmount = available / 2;
        uint256 borrowLimit = pair.borrowLimit();
        if (borrowLimit != 0 && borrowAmount > borrowLimit) borrowAmount = borrowLimit;
        if (borrowAmount < minBorrow) return;

        (uint256 ltvPrecision,,,) = pair.getConstants();
        uint256 minUnderlying = (borrowAmount * ltvPrecision) / pair.maxLTV();
        uint256 collateralAmount = minUnderlying * 2;
        address underlying = pair.underlying();

        deal(underlying, address(this), collateralAmount);
        IERC20(underlying).forceApprove(address(pair), collateralAmount);

        pair.borrow(borrowAmount, collateralAmount, address(this));
    }

    function _seedPair(IResupplyPair pair) internal {
        address[] memory pairs = new address[](1);
        pairs[0] = address(pair);
        _mockPairs(pairs);
        _ensureDebt(pair);
    }

    function _mockPairs(address[] memory pairs) internal {
        vm.mockCall(
            address(registry),
            abi.encodeWithSelector(IResupplyRegistry.getAllPairAddresses.selector),
            abi.encode(pairs)
        );
    }

    function _ensureFraxLoanWhitelist() internal {
        IFraxLoan lender = IFraxLoan(redemptionOperator.frxUsdFlashLender());
        if (!lender.onlyWhitelist()) return;
        if (lender.isExempt(address(redemptionOperator))) return;

        address setter = lender.whitelistSetter();
        if (setter == address(0)) {
            setter = lender.timelockAddress();
        }
        vm.prank(setter);
        lender.setExempt(address(redemptionOperator), true);
    }
}
