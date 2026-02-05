// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { RedemptionHandler } from "src/protocol/RedemptionHandler.sol";
import { Setup } from "test/e2e/Setup.sol";
import { MockOracle } from "test/mocks/MockOracle.sol";
import { Protocol } from "src/Constants.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IReusdOracle } from "src/interfaces/IReusdOracle.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { ICurveExchange } from "src/interfaces/curve/ICurveExchange.sol";

contract RedemptionHandlerTest is Setup {
    using SafeERC20 for IERC20;

    MockOracle mockOracle;
    address redemptionOperator;

    function setUp() public override {
        super.setUp();
        deployDefaultLendingPairs();
        mockOracle = new MockOracle("Mock Oracle", 1e18);
        redemptionOperator = address(0xBEEF);
    }

    function test_SetBaseRedemptionFee() public {
        vm.startPrank(address(core));
        uint256 newFee = 5e16; // 5%
        redemptionHandler.setBaseRedemptionFee(newFee);
        assertEq(redemptionHandler.baseRedemptionFee(), newFee);
        vm.stopPrank();
    }

    function test_SetDiscountInfo() public {
        vm.startPrank(address(core));
        uint256 newRate = 2e17;
        uint256 newMaxUsage = 4e17;
        uint256 newMaxDiscount = 1e14;
        redemptionHandler.setDiscountInfo(newRate, newMaxUsage, newMaxDiscount);
        assertEq(redemptionHandler.usageDecayRate(), newRate);
        assertEq(redemptionHandler.maxUsage(), newMaxUsage);
        assertEq(redemptionHandler.maxDiscount(), newMaxDiscount);
        vm.stopPrank();
    }

    function test_SetUnderlyingOracle() public {
        vm.startPrank(address(core));
        redemptionHandler.setUnderlyingOracle(address(mockOracle));
        assertEq(redemptionHandler.underlyingOracle(), address(mockOracle));
        vm.stopPrank();
    }

    function test_AccessControl() public {
        vm.expectRevert("!core");
        redemptionHandler.setBaseRedemptionFee(1e16);

        vm.expectRevert("!core");
        redemptionHandler.setDiscountInfo(1e17, 3e17, 5e14);

        vm.expectRevert("!core");
        redemptionHandler.setUnderlyingOracle(address(0x123));
    }

    function test_InvalidFeeSettings() public {
        vm.startPrank(address(core));
        vm.expectRevert("fee too high");
        redemptionHandler.setBaseRedemptionFee(2e18);
        vm.expectRevert("max discount exceeds base redemption fee");
        redemptionHandler.setDiscountInfo(
            1e17, // rate
            3e17, // max usage
            2e16  // max discount
        );
        vm.stopPrank();
    }

    function test_GetRedemptionFeePct() public {
        uint256 feePct = redemptionHandler.getRedemptionFeePct(address(testPair), 10_000e18);
        assertGt(feePct, 0, "Fee should be greater than 0");
        assertLe(feePct, 1e18, "Fee should not exceed 100%");
    }

    function test_PreviewRedeem() public {
        uint256 redeemAmount = 1000e18;
        (
            uint256 returnedUnderlying, 
            uint256 returnedCollateral, 
            uint256 fee
        ) = redemptionHandler.previewRedeem(address(testPair), redeemAmount);
        assertGt(fee, 0, "Fee should be greater than 0");
        assertLe(fee, 1e18, "Fee should not exceed 100%");
    }

    function test_RedemptionGuard() public {
        vm.prank(address(core));
        redemptionHandler.updateGuardSettings(true, 98e16);

        vm.mockCall(
            address(reusdOracle),
            abi.encodeWithSelector(IReusdOracle.oraclePriceAsCrvusd.selector),
            abi.encode(1e18)
        );

        vm.expectRevert("redemption guarded");
        redemptionHandler.redeemFromPair(address(testPair), 0, type(uint256).max, address(this), true);
    }

    function test_RedemptionGuardAllowsOperator() public {
        RedemptionHandler rh = new RedemptionHandler(address(core), Protocol.REGISTRY, address(0));
        vm.startPrank(address(core));
        rh.updateGuardSettings(true, 98e16);
        vm.stopPrank();

        IResupplyRegistry reg = IResupplyRegistry(rh.registry());

        vm.startPrank(Protocol.CORE);
        reg.setAddress("REDEMPTION_OPERATOR", address(redemptionOperator));
        reg.setRedemptionHandler(address(rh));
        vm.stopPrank();

        (address pairToRedeem, uint256 redeemAmount) = _requireRedeemablePair(rh, reg);

        address debtToken = reg.token();
        deal(debtToken, redemptionOperator, redeemAmount);

        vm.prank(redemptionOperator);
        IERC20(debtToken).forceApprove(address(rh), type(uint256).max);

        vm.prank(redemptionOperator);
        uint256 received = rh.redeemFromPair(
            pairToRedeem,
            redeemAmount,
            type(uint256).max,
            address(this),
            true
        );
        assertGt(received, 0, "no collateral received");
    }

    function test_RedemptionGuardDisabled_AllowsPermissionless() public {
        RedemptionHandler rh = new RedemptionHandler(address(core), Protocol.REGISTRY, address(0));
        vm.prank(address(core));
        rh.updateGuardSettings(false, 98e16);

        IResupplyRegistry reg = IResupplyRegistry(rh.registry());

        vm.prank(Protocol.CORE);
        reg.setRedemptionHandler(address(rh));

        (address pairToRedeem, uint256 redeemAmount) = _requireRedeemablePair(rh, reg);

        address debtToken = reg.token();
        deal(debtToken, address(this), redeemAmount);
        IERC20(debtToken).forceApprove(address(rh), type(uint256).max);

        uint256 received = rh.redeemFromPair(
            pairToRedeem,
            redeemAmount,
            type(uint256).max,
            address(this),
            true
        );
        assertGt(received, 0, "no collateral received");
    }

    function test_RedemptionGuardBelowThreshold_AllowsPermissionless() public {
        RedemptionHandler rh = new RedemptionHandler(address(core), Protocol.REGISTRY, address(0));
        vm.prank(address(core));
        rh.updateGuardSettings(true, 98e16);

        IResupplyRegistry reg = IResupplyRegistry(rh.registry());

        vm.startPrank(Protocol.CORE);
        reg.setAddress("REUSD_ORACLE", address(reusdOracle));
        reg.setRedemptionHandler(address(rh));
        vm.stopPrank();

        vm.mockCall(
            address(reusdOracle),
            abi.encodeWithSelector(IReusdOracle.oraclePriceAsCrvusd.selector),
            abi.encode(97e16)
        );

        (address pairToRedeem, uint256 redeemAmount) = _requireRedeemablePair(rh, reg);

        address debtToken = reg.token();
        deal(debtToken, address(this), redeemAmount);
        IERC20(debtToken).forceApprove(address(rh), type(uint256).max);

        uint256 received = rh.redeemFromPair(
            pairToRedeem,
            redeemAmount,
            type(uint256).max,
            address(this),
            true
        );
        assertGt(received, 0, "no collateral received");
    }

    function test_GuardSettingsUpdated() public {
        vm.prank(address(core));
        redemptionHandler.updateGuardSettings(true, 97e16);
        assertTrue(redemptionHandler.guardEnabled());
        assertEq(redemptionHandler.permissionlessPriceThreshold(), 97e16);
    }

    function _requireRedeemablePair(RedemptionHandler rh, IResupplyRegistry reg)
        internal
        returns (address pairToRedeem, uint256 redeemAmount)
    {
        _skewReusdScrvPool();
        (pairToRedeem, redeemAmount) = _findRedeemablePair(rh, reg);
        require(pairToRedeem != address(0), "no redeemable pair on fork");
    }

    function _findRedeemablePair(RedemptionHandler rh, IResupplyRegistry reg)
        internal
        view
        returns (address pairToRedeem, uint256 redeemAmount)
    {
        address[] memory pairs = reg.getAllPairAddresses();
        for (uint256 i = 0; i < pairs.length; i++) {
            address pair = pairs[i];
            uint256 minRedemption = IResupplyPair(pair).minimumRedemption();
            uint256 maxRedeemable = rh.getMaxRedeemableDebt(pair);
            if (maxRedeemable >= minRedemption) {
                return (pair, minRedemption);
            }
        }
    }

    function _skewReusdScrvPool() internal {
        address pool = Protocol.REUSD_SCRVUSD_POOL;
        address token = ICurveExchange(pool).coins(0);

        uint256 amount = 10_000_000e18;
        deal(token, address(this), amount);
        IERC20(token).forceApprove(pool, amount);
        ICurveExchange(pool).exchange(int128(0), int128(1), amount, 0, address(this));
    }
}
