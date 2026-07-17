// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Test} from "forge-std/Test.sol";
import {Core} from "src/dao/Core.sol";
import {Treasury} from "src/dao/Treasury.sol";
import {TreasuryStableDiversification} from "src/dao/TreasuryStableDiversification.sol";

interface ICurvePoolView {
    function get_dy(int128 i, int128 j, uint256 dx) external view returns (uint256);
    function stored_rates() external view returns (uint256[] memory);
}

contract MockDiversificationToken is ERC20 {
    uint8 private immutable _TOKEN_DECIMALS;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _TOKEN_DECIMALS = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _TOKEN_DECIMALS;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockCurveStableSwapPool {
    using SafeERC20 for IERC20;

    IERC20Metadata public immutable COIN0;
    IERC20Metadata public immutable COIN1;
    uint256 public outputBps = 10_000;
    bool public enforceMinOut = true;
    bool public useVaultRates;
    uint256 public rawSpotPrice = 1e18;
    uint256 public rawEmaPrice = 1e18;

    constructor(IERC20Metadata coin0_, IERC20Metadata coin1_) {
        COIN0 = coin0_;
        COIN1 = coin1_;
    }

    function coins(uint256 index) external view returns (address) {
        if (index == 0) return address(COIN0);
        if (index == 1) return address(COIN1);
        revert("coin out of range");
    }

    function price_oracle(uint256 index) external view returns (uint256) {
        require(index == 0, "price out of range");
        return rawEmaPrice;
    }

    function last_prices(uint256 index) external view returns (uint256) {
        require(index == 0, "price out of range");
        return rawSpotPrice;
    }

    function last_price(uint256 index) external view returns (uint256) {
        require(index == 0, "price out of range");
        return rawSpotPrice;
    }

    function get_p(uint256 index) external view returns (uint256) {
        require(index == 0, "price out of range");
        return rawSpotPrice;
    }

    function setOutputBps(uint256 outputBps_) external {
        outputBps = outputBps_;
    }

    function setEnforceMinOut(bool enforceMinOut_) external {
        enforceMinOut = enforceMinOut_;
    }

    function setUseVaultRates(bool useVaultRates_) external {
        useVaultRates = useVaultRates_;
    }

    function setRawPrices(uint256 rawSpotPrice_, uint256 rawEmaPrice_) external {
        rawSpotPrice = rawSpotPrice_;
        rawEmaPrice = rawEmaPrice_;
    }

    function exchange(int128 i, int128 j, uint256 dx, uint256 minDy) external returns (uint256 dy) {
        IERC20Metadata input = i == 0 ? COIN0 : COIN1;
        IERC20Metadata output = j == 0 ? COIN0 : COIN1;
        require(address(input) != address(output), "same coin");

        IERC20(address(input)).safeTransferFrom(msg.sender, address(this), dx);
        dy = useVaultRates ? _vaultRateOutput(input, output, dx) : _scaleAmount(dx, input.decimals(), output.decimals());
        dy = dy * outputBps / 10_000;
        if (enforceMinOut) require(dy >= minDy, "slippage");
        IERC20(address(output)).safeTransfer(msg.sender, dy);
    }

    function _vaultRateOutput(IERC20Metadata input, IERC20Metadata output, uint256 amount)
        internal
        view
        returns (uint256)
    {
        (uint256 stableAmount, uint8 stableDecimals) = _stableAmountForToken(address(input), amount);
        try IERC4626(address(output)).asset() returns (address vaultAsset) {
            return IERC4626(address(output))
                .convertToShares(_scaleAmount(stableAmount, stableDecimals, IERC20Metadata(vaultAsset).decimals()));
        } catch {}

        return _scaleAmount(stableAmount, stableDecimals, output.decimals());
    }

    function _stableAmountForToken(address token, uint256 amount) internal view returns (uint256, uint8) {
        try IERC4626(token).asset() returns (address vaultAsset) {
            return (IERC4626(token).convertToAssets(amount), IERC20Metadata(vaultAsset).decimals());
        } catch {}

        return (amount, IERC20Metadata(token).decimals());
    }

    function _scaleAmount(uint256 amount, uint8 fromDecimals, uint8 toDecimals) internal pure returns (uint256) {
        if (fromDecimals == toDecimals) return amount;
        if (fromDecimals < toDecimals) return amount * 10 ** (toDecimals - fromDecimals);
        return amount / 10 ** (fromDecimals - toDecimals);
    }
}

contract MockDiversificationVault is ERC4626 {
    constructor(IERC20 asset_) ERC20("Vault Stable", "vSTBL") ERC4626(asset_) {}
}

contract TreasuryStableDiversificationTest is Test {
    Core internal core;
    Treasury internal treasury;
    TreasuryStableDiversification internal diversifier;

    MockDiversificationToken internal asset;
    MockDiversificationToken internal usdc;
    MockDiversificationToken internal usdt;
    MockDiversificationToken internal dai;
    MockDiversificationToken internal frxUsd;
    MockDiversificationToken internal sdola;

    address internal recipient = makeAddr("recipient");

    function setUp() public {
        core = new Core(address(this), 7 days);

        asset = new MockDiversificationToken("Curve USD", "crvUSD", 18);
        usdc = new MockDiversificationToken("USD Coin", "USDC", 6);
        usdt = new MockDiversificationToken("Tether USD", "USDT", 6);
        dai = new MockDiversificationToken("Dai Stablecoin", "DAI", 18);
        frxUsd = new MockDiversificationToken("Frax USD", "frxUSD", 18);
        sdola = new MockDiversificationToken("Staked DOLA", "sDOLA", 18);

        treasury = new Treasury(address(core));
        diversifier = new TreasuryStableDiversification(address(core), address(treasury), address(asset), 100);
        core.execute(
            address(treasury),
            abi.encodeCall(Treasury.setTokenApproval, (address(asset), address(diversifier), type(uint256).max))
        );
    }

    function test_onlyCoreCanSetTargets() public {
        TreasuryStableDiversification.Target[] memory targets = new TreasuryStableDiversification.Target[](1);
        targets[0] = TreasuryStableDiversification.Target({
            token: address(usdc),
            weight: 1,
            swapPool: address(new MockCurveStableSwapPool(asset, usdc)),
            vault: address(0),
            inputToken: address(0),
            stakedAsset: address(0),
            maxPrice: 0,
            maxSpotEmaDeviationBps: 0,
            executionBufferBps: 0
        });

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        diversifier.setTargets(targets);

        vm.prank(address(core));
        diversifier.setTargets(targets);

        assertEq(diversifier.targetCount(), 1);
        assertEq(diversifier.totalWeight(), 1);
    }

    function test_onlyCoreCanConfigureSwapOperators() public {
        address keeper = makeAddr("keeper");

        assertFalse(diversifier.useOperators());

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        diversifier.setUseOperators(true);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        diversifier.setOperator(keeper, true);

        vm.prank(address(core));
        diversifier.setUseOperators(true);
        assertTrue(diversifier.useOperators());

        vm.prank(address(core));
        diversifier.setOperator(keeper, true);
        assertTrue(diversifier.operators(keeper));

        vm.prank(address(core));
        diversifier.setOperator(keeper, false);
        assertFalse(diversifier.operators(keeper));
    }

    function test_onlyCoreCanConfigureMinimumTreasuryAssetBalance() public {
        assertEq(diversifier.minTreasuryAssetBalance(), 0);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        diversifier.setMinTreasuryAssetBalance(100_000e18);

        vm.prank(address(core));
        diversifier.setMinTreasuryAssetBalance(100_000e18);

        assertEq(diversifier.minTreasuryAssetBalance(), 100_000e18);
    }

    function test_swapRequiresOperatorOnlyWhenGuarded() public {
        address keeper = makeAddr("keeper");
        MockCurveStableSwapPool usdcPool = new MockCurveStableSwapPool(asset, usdc);
        usdc.mint(address(usdcPool), 1_000_000e6);
        asset.mint(address(treasury), 100e18);

        TreasuryStableDiversification.Target[] memory targets = new TreasuryStableDiversification.Target[](1);
        targets[0] = TreasuryStableDiversification.Target({
            token: address(usdc),
            weight: 1,
            swapPool: address(usdcPool),
            vault: address(0),
            inputToken: address(0),
            stakedAsset: address(0),
            maxPrice: 0,
            maxSpotEmaDeviationBps: 0,
            executionBufferBps: 0
        });
        vm.prank(address(core));
        diversifier.setTargets(targets);

        vm.prank(address(core));
        diversifier.setUseOperators(true);

        vm.expectRevert(
            abi.encodeWithSelector(
                TreasuryStableDiversification.TreasuryStableDiversification_NotOperator.selector, keeper
            )
        );
        vm.prank(keeper);
        diversifier.swap(100e18);

        vm.prank(address(core));
        diversifier.setOperator(keeper, true);

        vm.prank(keeper);
        diversifier.swap(100e18);

        assertEq(asset.balanceOf(address(treasury)), 0);
        assertEq(usdc.balanceOf(address(treasury)), 100e6);
    }

    function test_swapCapsTreasuryPullToLeaveMinimumAssetBalance() public {
        MockCurveStableSwapPool usdcPool = new MockCurveStableSwapPool(asset, usdc);
        usdc.mint(address(usdcPool), 1_000_000e6);
        asset.mint(address(treasury), 100e18);

        TreasuryStableDiversification.Target[] memory targets = new TreasuryStableDiversification.Target[](1);
        targets[0] = TreasuryStableDiversification.Target({
            token: address(usdc),
            weight: 1,
            swapPool: address(usdcPool),
            vault: address(0),
            inputToken: address(0),
            stakedAsset: address(0),
            maxPrice: 0,
            maxSpotEmaDeviationBps: 0,
            executionBufferBps: 0
        });
        vm.prank(address(core));
        diversifier.setTargets(targets);
        vm.prank(address(core));
        diversifier.setMinTreasuryAssetBalance(40e18);

        uint256 assetAmount = diversifier.swap(100e18);

        assertEq(assetAmount, 60e18);
        assertEq(asset.balanceOf(address(treasury)), 40e18);
        assertEq(asset.balanceOf(address(diversifier)), 0);
        assertEq(usdc.balanceOf(address(treasury)), 60e6);
    }

    function test_setTargetsAllowsInputTokenWithoutEarlierOutput() public {
        MockDiversificationVault sfrxUsd = new MockDiversificationVault(IERC20(address(frxUsd)));
        MockCurveStableSwapPool sfrxUsdPool = new MockCurveStableSwapPool(frxUsd, sfrxUsd);

        TreasuryStableDiversification.Target[] memory targets = new TreasuryStableDiversification.Target[](1);
        targets[0] = TreasuryStableDiversification.Target({
            token: address(sfrxUsd),
            weight: 0,
            swapPool: address(sfrxUsdPool),
            vault: address(0),
            inputToken: address(frxUsd),
            stakedAsset: address(0),
            maxPrice: 0,
            maxSpotEmaDeviationBps: 0,
            executionBufferBps: 0
        });

        vm.prank(address(core));
        diversifier.setTargets(targets);

        assertEq(diversifier.targetCount(), 1);
        assertEq(diversifier.totalWeight(), 0);
    }

    function test_swapPullsTreasuryAssetsAndSplitsByWeight() public {
        MockCurveStableSwapPool usdcPool = new MockCurveStableSwapPool(asset, usdc);
        MockCurveStableSwapPool usdtPool = new MockCurveStableSwapPool(asset, usdt);
        usdc.mint(address(usdcPool), 1_000_000e6);
        usdt.mint(address(usdtPool), 1_000_000e6);
        asset.mint(address(treasury), 100e18);

        TreasuryStableDiversification.Target[] memory targets = new TreasuryStableDiversification.Target[](2);
        targets[0] = TreasuryStableDiversification.Target({
            token: address(usdc),
            weight: 1,
            swapPool: address(usdcPool),
            vault: address(0),
            inputToken: address(0),
            stakedAsset: address(0),
            maxPrice: 0,
            maxSpotEmaDeviationBps: 0,
            executionBufferBps: 0
        });
        targets[1] = TreasuryStableDiversification.Target({
            token: address(usdt),
            weight: 3,
            swapPool: address(usdtPool),
            vault: address(0),
            inputToken: address(0),
            stakedAsset: address(0),
            maxPrice: 0,
            maxSpotEmaDeviationBps: 0,
            executionBufferBps: 0
        });
        vm.prank(address(core));
        diversifier.setTargets(targets);
        assertFalse(diversifier.useOperators());

        vm.prank(makeAddr("keeper"));
        uint256 assetAmount = diversifier.swap(100e18);

        assertEq(assetAmount, 100e18);
        assertEq(asset.balanceOf(address(treasury)), 0);
        assertEq(asset.balanceOf(address(diversifier)), 0);
        assertEq(usdc.balanceOf(address(treasury)), 25e6);
        assertEq(usdt.balanceOf(address(treasury)), 75e6);
        assertEq(usdc.balanceOf(address(diversifier)), 0);
        assertEq(usdt.balanceOf(address(diversifier)), 0);
    }

    function test_swapIncludesDirectlyTransferredAssetBalance() public {
        MockCurveStableSwapPool usdcPool = new MockCurveStableSwapPool(asset, usdc);
        usdc.mint(address(usdcPool), 1_000_000e6);
        asset.mint(address(treasury), 90e18);
        asset.mint(address(diversifier), 10e18);

        TreasuryStableDiversification.Target[] memory targets = new TreasuryStableDiversification.Target[](1);
        targets[0] = TreasuryStableDiversification.Target({
            token: address(usdc),
            weight: 1,
            swapPool: address(usdcPool),
            vault: address(0),
            inputToken: address(0),
            stakedAsset: address(0),
            maxPrice: 0,
            maxSpotEmaDeviationBps: 0,
            executionBufferBps: 0
        });
        vm.prank(address(core));
        diversifier.setTargets(targets);

        uint256 assetAmount = diversifier.swap(90e18);

        assertEq(assetAmount, 100e18);
        assertEq(usdc.balanceOf(address(treasury)), 100e6);
        assertEq(asset.balanceOf(address(diversifier)), 0);
    }

    function test_swapUsesOutputDeltaForMinOut() public {
        MockCurveStableSwapPool usdcPool = new MockCurveStableSwapPool(asset, usdc);
        usdcPool.setOutputBps(9_800);
        usdcPool.setEnforceMinOut(false);
        usdc.mint(address(usdcPool), 1_000_000e6);
        usdc.mint(address(diversifier), 1e6);
        asset.mint(address(treasury), 100e18);

        TreasuryStableDiversification.Target[] memory targets = new TreasuryStableDiversification.Target[](1);
        targets[0] = TreasuryStableDiversification.Target({
            token: address(usdc),
            weight: 1,
            swapPool: address(usdcPool),
            vault: address(0),
            inputToken: address(0),
            stakedAsset: address(0),
            maxPrice: 0,
            maxSpotEmaDeviationBps: 0,
            executionBufferBps: 0
        });
        vm.prank(address(core));
        diversifier.setTargets(targets);

        vm.expectRevert(
            abi.encodeWithSelector(
                TreasuryStableDiversification.TreasuryStableDiversification_InsufficientOutput.selector,
                address(usdc),
                99e6,
                98e6
            )
        );
        diversifier.swap(100e18);
    }

    function test_swapReturnsDonatedOutputAfterDeltaMinOutCheck() public {
        MockCurveStableSwapPool usdcPool = new MockCurveStableSwapPool(asset, usdc);
        usdc.mint(address(usdcPool), 1_000_000e6);
        usdc.mint(address(diversifier), 1e6);
        asset.mint(address(treasury), 100e18);

        TreasuryStableDiversification.Target[] memory targets = new TreasuryStableDiversification.Target[](1);
        targets[0] = TreasuryStableDiversification.Target({
            token: address(usdc),
            weight: 1,
            swapPool: address(usdcPool),
            vault: address(0),
            inputToken: address(0),
            stakedAsset: address(0),
            maxPrice: 0,
            maxSpotEmaDeviationBps: 0,
            executionBufferBps: 0
        });
        vm.prank(address(core));
        diversifier.setTargets(targets);

        uint256 assetAmount = diversifier.swap(100e18);

        assertEq(assetAmount, 100e18);
        assertEq(usdc.balanceOf(address(treasury)), 101e6);
        assertEq(usdc.balanceOf(address(diversifier)), 0);
    }

    function test_swapIncludesDirectlyTransferredStakedAssetBalance() public {
        MockDiversificationVault stakedAsset = new MockDiversificationVault(IERC20(address(asset)));
        MockCurveStableSwapPool sdolaPool = new MockCurveStableSwapPool(stakedAsset, sdola);
        sdola.mint(address(sdolaPool), 1_000_000e18);
        asset.mint(address(this), 10e18);
        asset.mint(address(treasury), 100e18);

        asset.approve(address(stakedAsset), 10e18);
        stakedAsset.deposit(10e18, address(diversifier));

        TreasuryStableDiversification.Target[] memory targets = new TreasuryStableDiversification.Target[](1);
        targets[0] = TreasuryStableDiversification.Target({
            token: address(sdola),
            weight: 1,
            swapPool: address(sdolaPool),
            vault: address(0),
            inputToken: address(0),
            stakedAsset: address(stakedAsset),
            maxPrice: 0,
            maxSpotEmaDeviationBps: 0,
            executionBufferBps: 0
        });
        vm.prank(address(core));
        diversifier.setTargets(targets);

        uint256 assetAmount = diversifier.swap(100e18);

        assertEq(assetAmount, 100e18);
        assertEq(stakedAsset.balanceOf(address(diversifier)), 0);
        assertEq(sdola.balanceOf(address(treasury)), 110e18);
        assertEq(sdola.balanceOf(address(diversifier)), 0);
    }

    function test_swapCanStakeAssetBeforeSwappingTarget() public {
        MockDiversificationVault stakedAsset = new MockDiversificationVault(IERC20(address(asset)));
        MockCurveStableSwapPool sdolaPool = new MockCurveStableSwapPool(stakedAsset, sdola);
        sdola.mint(address(sdolaPool), 1_000_000e18);
        asset.mint(address(treasury), 100e18);

        TreasuryStableDiversification.Target[] memory targets = new TreasuryStableDiversification.Target[](1);
        targets[0] = TreasuryStableDiversification.Target({
            token: address(sdola),
            weight: 1,
            swapPool: address(sdolaPool),
            vault: address(0),
            inputToken: address(0),
            stakedAsset: address(stakedAsset),
            maxPrice: 0,
            maxSpotEmaDeviationBps: 0,
            executionBufferBps: 0
        });
        vm.prank(address(core));
        diversifier.setTargets(targets);
        assertEq(diversifier.totalWeight(), 1);

        uint256 assetAmount = diversifier.swap(100e18);

        assertEq(assetAmount, 100e18);
        assertEq(asset.balanceOf(address(treasury)), 0);
        assertEq(asset.balanceOf(address(diversifier)), 0);
        assertEq(stakedAsset.balanceOf(address(diversifier)), 0);
        assertEq(stakedAsset.balanceOf(address(sdolaPool)), 100e18);
        assertEq(sdola.balanceOf(address(treasury)), 100e18);
        assertEq(sdola.balanceOf(address(diversifier)), 0);
    }

    function test_swapRevertsWhenStakedInputMissesPricePerShareGuard() public {
        MockDiversificationVault stakedAsset = new MockDiversificationVault(IERC20(address(asset)));
        MockCurveStableSwapPool sdolaPool = new MockCurveStableSwapPool(stakedAsset, sdola);
        sdolaPool.setUseVaultRates(true);
        sdolaPool.setOutputBps(9_800);
        sdolaPool.setEnforceMinOut(false);
        address yieldOwner = makeAddr("yieldOwner");
        asset.mint(yieldOwner, 100e18);
        sdola.mint(address(sdolaPool), 1_000_000e18);
        asset.mint(address(treasury), 100e18);

        vm.startPrank(yieldOwner);
        asset.approve(address(stakedAsset), 100e18);
        stakedAsset.deposit(100e18, yieldOwner);
        vm.stopPrank();
        asset.mint(address(stakedAsset), 100e18);

        TreasuryStableDiversification.Target[] memory targets = new TreasuryStableDiversification.Target[](1);
        targets[0] = TreasuryStableDiversification.Target({
            token: address(sdola),
            weight: 1,
            swapPool: address(sdolaPool),
            vault: address(0),
            inputToken: address(0),
            stakedAsset: address(stakedAsset),
            maxPrice: 0,
            maxSpotEmaDeviationBps: 0,
            executionBufferBps: 0
        });
        vm.prank(address(core));
        diversifier.setTargets(targets);

        vm.expectRevert(
            abi.encodeWithSelector(
                TreasuryStableDiversification.TreasuryStableDiversification_InsufficientOutput.selector,
                address(sdola),
                99e18 - 1,
                98e18 - 1
            )
        );
        diversifier.swap(100e18);
    }

    function test_swapCanUseIntermediateTokenAsNextInput() public {
        MockDiversificationVault sfrxUsd = new MockDiversificationVault(IERC20(address(frxUsd)));
        MockCurveStableSwapPool frxUsdPool = new MockCurveStableSwapPool(asset, frxUsd);
        MockCurveStableSwapPool sfrxUsdPool = new MockCurveStableSwapPool(frxUsd, sfrxUsd);
        sfrxUsdPool.setUseVaultRates(true);

        asset.mint(address(treasury), 100e18);
        frxUsd.mint(address(diversifier), 7e18);
        frxUsd.mint(address(frxUsdPool), 1_000_000e18);
        frxUsd.mint(address(this), 100e18);
        frxUsd.approve(address(sfrxUsd), 100e18);
        sfrxUsd.deposit(100e18, address(sfrxUsdPool));
        frxUsd.mint(address(sfrxUsd), 100e18);

        TreasuryStableDiversification.Target[] memory targets = new TreasuryStableDiversification.Target[](2);
        targets[0] = TreasuryStableDiversification.Target({
            token: address(frxUsd),
            weight: 1,
            swapPool: address(frxUsdPool),
            vault: address(0),
            inputToken: address(0),
            stakedAsset: address(0),
            maxPrice: 0,
            maxSpotEmaDeviationBps: 0,
            executionBufferBps: 0
        });
        targets[1] = TreasuryStableDiversification.Target({
            token: address(sfrxUsd),
            weight: 0,
            swapPool: address(sfrxUsdPool),
            vault: address(0),
            inputToken: address(frxUsd),
            stakedAsset: address(0),
            maxPrice: 0,
            maxSpotEmaDeviationBps: 0,
            executionBufferBps: 0
        });
        vm.prank(address(core));
        diversifier.setTargets(targets);
        assertEq(diversifier.totalWeight(), 1);

        uint256 assetAmount = diversifier.swap(100e18);

        assertEq(assetAmount, 100e18);
        assertEq(asset.balanceOf(address(treasury)), 0);
        assertEq(asset.balanceOf(address(diversifier)), 0);
        assertEq(frxUsd.balanceOf(address(treasury)), 0);
        assertEq(frxUsd.balanceOf(address(diversifier)), 0);
        assertEq(frxUsd.balanceOf(address(sfrxUsdPool)), 107e18);
        assertEq(sfrxUsd.balanceOf(address(treasury)), 53.5e18);
        assertEq(sfrxUsd.balanceOf(address(diversifier)), 0);
    }

    function test_swapCanReturnStakedAssetSharesToTreasury() public {
        MockDiversificationVault stakedAsset = new MockDiversificationVault(IERC20(address(asset)));
        address yieldOwner = makeAddr("yieldOwner");
        asset.mint(yieldOwner, 100e18);

        vm.startPrank(yieldOwner);
        asset.approve(address(stakedAsset), 100e18);
        stakedAsset.deposit(100e18, yieldOwner);
        vm.stopPrank();

        asset.mint(address(stakedAsset), 100e18);
        asset.mint(address(treasury), 100e18);

        TreasuryStableDiversification.Target[] memory targets = new TreasuryStableDiversification.Target[](1);
        targets[0] = TreasuryStableDiversification.Target({
            token: address(stakedAsset),
            weight: 1,
            swapPool: address(0),
            vault: address(0),
            inputToken: address(0),
            stakedAsset: address(stakedAsset),
            maxPrice: 0,
            maxSpotEmaDeviationBps: 0,
            executionBufferBps: 0
        });
        vm.prank(address(core));
        diversifier.setTargets(targets);

        uint256 assetAmount = diversifier.swap(100e18);

        assertEq(assetAmount, 100e18);
        assertEq(asset.balanceOf(address(treasury)), 0);
        assertEq(asset.balanceOf(address(diversifier)), 0);
        assertEq(stakedAsset.balanceOf(address(treasury)), 50e18);
        assertEq(stakedAsset.balanceOf(address(diversifier)), 0);
    }

    function test_swapRevertsWhenOutputMissesDeviationGuard() public {
        MockCurveStableSwapPool usdcPool = new MockCurveStableSwapPool(asset, usdc);
        usdcPool.setOutputBps(9_800);
        usdcPool.setEnforceMinOut(false);
        usdc.mint(address(usdcPool), 1_000_000e6);
        asset.mint(address(treasury), 100e18);

        TreasuryStableDiversification.Target[] memory targets = new TreasuryStableDiversification.Target[](1);
        targets[0] = TreasuryStableDiversification.Target({
            token: address(usdc),
            weight: 1,
            swapPool: address(usdcPool),
            vault: address(0),
            inputToken: address(0),
            stakedAsset: address(0),
            maxPrice: 0,
            maxSpotEmaDeviationBps: 0,
            executionBufferBps: 0
        });
        vm.prank(address(core));
        diversifier.setTargets(targets);

        vm.expectRevert(
            abi.encodeWithSelector(
                TreasuryStableDiversification.TreasuryStableDiversification_InsufficientOutput.selector,
                address(usdc),
                99e6,
                98e6
            )
        );
        diversifier.swap(100e18);
    }

    function test_swapWithPriceGuardUsesMaxPriceAndExecutionBuffer() public {
        MockCurveStableSwapPool usdcPool = new MockCurveStableSwapPool(asset, usdc);
        usdcPool.setOutputBps(9_950);
        usdc.mint(address(usdcPool), 1_000_000e6);
        asset.mint(address(treasury), 100e18);

        TreasuryStableDiversification.Target[] memory targets = new TreasuryStableDiversification.Target[](1);
        targets[0] = TreasuryStableDiversification.Target({
            token: address(usdc),
            weight: 1,
            swapPool: address(usdcPool),
            vault: address(0),
            inputToken: address(0),
            stakedAsset: address(0),
            maxPrice: 1e18,
            maxSpotEmaDeviationBps: 100,
            executionBufferBps: 100
        });
        vm.prank(address(core));
        diversifier.setTargets(targets);

        uint256 assetAmount = diversifier.swap(100e18);

        assertEq(assetAmount, 100e18);
        assertEq(asset.balanceOf(address(treasury)), 0);
        assertEq(usdc.balanceOf(address(treasury)), 99.5e6);
    }

    function test_swapWithPriceGuardNormalizesStakedInputValue() public {
        MockDiversificationVault stakedAsset = new MockDiversificationVault(IERC20(address(asset)));
        MockCurveStableSwapPool sdolaPool = new MockCurveStableSwapPool(stakedAsset, sdola);
        sdolaPool.setUseVaultRates(true);
        sdolaPool.setOutputBps(9_950);
        sdolaPool.setRawPrices(0.5e18, 0.5e18);
        address yieldOwner = makeAddr("yieldOwner");
        asset.mint(yieldOwner, 100e18);
        sdola.mint(address(sdolaPool), 1_000_000e18);
        asset.mint(address(treasury), 100e18);

        vm.startPrank(yieldOwner);
        asset.approve(address(stakedAsset), 100e18);
        stakedAsset.deposit(100e18, yieldOwner);
        vm.stopPrank();
        asset.mint(address(stakedAsset), 100e18);

        TreasuryStableDiversification.Target[] memory targets = new TreasuryStableDiversification.Target[](1);
        targets[0] = TreasuryStableDiversification.Target({
            token: address(sdola),
            weight: 1,
            swapPool: address(sdolaPool),
            vault: address(0),
            inputToken: address(0),
            stakedAsset: address(stakedAsset),
            maxPrice: 1e18,
            maxSpotEmaDeviationBps: 100,
            executionBufferBps: 100
        });
        vm.prank(address(core));
        diversifier.setTargets(targets);

        uint256 assetAmount = diversifier.swap(100e18);

        assertEq(assetAmount, 100e18);
        assertEq(asset.balanceOf(address(treasury)), 0);
        assertEq(sdola.balanceOf(address(treasury)), 99.5e18 - 1);
    }

    function test_swapWithPriceGuardDoesNotDoubleCountVaultTargetPps() public {
        MockDiversificationVault vaultTarget = new MockDiversificationVault(IERC20(address(asset)));
        MockCurveStableSwapPool vaultPool = new MockCurveStableSwapPool(vaultTarget, asset);
        vaultPool.setUseVaultRates(true);
        vaultPool.setRawPrices(0.98e18, 0.98e18);

        address yieldOwner = makeAddr("yieldOwner");
        asset.mint(yieldOwner, 100e18);
        vm.startPrank(yieldOwner);
        asset.approve(address(vaultTarget), 100e18);
        vaultTarget.deposit(100e18, yieldOwner);
        vm.stopPrank();
        asset.mint(address(vaultTarget), 100e18);

        asset.mint(address(this), 1_000e18);
        asset.approve(address(vaultTarget), 1_000e18);
        vaultTarget.deposit(1_000e18, address(vaultPool));
        asset.mint(address(treasury), 100e18);

        TreasuryStableDiversification.Target[] memory targets = new TreasuryStableDiversification.Target[](1);
        targets[0] = TreasuryStableDiversification.Target({
            token: address(vaultTarget),
            weight: 1,
            swapPool: address(vaultPool),
            vault: address(0),
            inputToken: address(0),
            stakedAsset: address(0),
            maxPrice: 1.01e18,
            maxSpotEmaDeviationBps: 100,
            executionBufferBps: 100
        });
        vm.prank(address(core));
        diversifier.setTargets(targets);

        vm.expectRevert(
            abi.encodeWithSelector(
                TreasuryStableDiversification.TreasuryStableDiversification_PriceOutOfRange.selector,
                1_020_408_163_265_306_123,
                1.01e18
            )
        );
        diversifier.swap(100e18);
    }

    function test_swapCanUseSpotEmaGuardWithoutMaxPrice() public {
        MockCurveStableSwapPool usdcPool = new MockCurveStableSwapPool(asset, usdc);
        usdcPool.setOutputBps(9_900);
        usdcPool.setRawPrices(2e18, 2e18);
        usdc.mint(address(usdcPool), 1_000_000e6);
        asset.mint(address(treasury), 100e18);

        TreasuryStableDiversification.Target[] memory targets = new TreasuryStableDiversification.Target[](1);
        targets[0] = TreasuryStableDiversification.Target({
            token: address(usdc),
            weight: 1,
            swapPool: address(usdcPool),
            vault: address(0),
            inputToken: address(0),
            stakedAsset: address(0),
            maxPrice: 0,
            maxSpotEmaDeviationBps: 100,
            executionBufferBps: 0
        });
        vm.prank(address(core));
        diversifier.setTargets(targets);

        uint256 assetAmount = diversifier.swap(100e18);

        assertEq(assetAmount, 100e18);
        assertEq(usdc.balanceOf(address(treasury)), 99e6);
    }

    function test_swapWithSpotEmaGuardWithoutMaxPriceRevertsWhenDeviationTooWide() public {
        MockCurveStableSwapPool usdcPool = new MockCurveStableSwapPool(asset, usdc);
        usdcPool.setRawPrices(1.02e18, 1e18);
        usdc.mint(address(usdcPool), 1_000_000e6);
        asset.mint(address(treasury), 100e18);

        TreasuryStableDiversification.Target[] memory targets = new TreasuryStableDiversification.Target[](1);
        targets[0] = TreasuryStableDiversification.Target({
            token: address(usdc),
            weight: 1,
            swapPool: address(usdcPool),
            vault: address(0),
            inputToken: address(0),
            stakedAsset: address(0),
            maxPrice: 0,
            maxSpotEmaDeviationBps: 100,
            executionBufferBps: 0
        });
        vm.prank(address(core));
        diversifier.setTargets(targets);

        vm.expectRevert(
            abi.encodeWithSelector(
                TreasuryStableDiversification.TreasuryStableDiversification_OracleVolatile.selector, 1e18, 1.02e18, 100
            )
        );
        diversifier.swap(100e18);
    }

    function test_swapWithPriceGuardRevertsWhenSpotAboveMaxPrice() public {
        MockCurveStableSwapPool usdcPool = new MockCurveStableSwapPool(asset, usdc);
        usdcPool.setRawPrices(1.02e18, 1.02e18);
        usdc.mint(address(usdcPool), 1_000_000e6);
        asset.mint(address(treasury), 100e18);

        TreasuryStableDiversification.Target[] memory targets = new TreasuryStableDiversification.Target[](1);
        targets[0] = TreasuryStableDiversification.Target({
            token: address(usdc),
            weight: 1,
            swapPool: address(usdcPool),
            vault: address(0),
            inputToken: address(0),
            stakedAsset: address(0),
            maxPrice: 1.01e18,
            maxSpotEmaDeviationBps: 100,
            executionBufferBps: 100
        });
        vm.prank(address(core));
        diversifier.setTargets(targets);

        vm.expectRevert(
            abi.encodeWithSelector(
                TreasuryStableDiversification.TreasuryStableDiversification_PriceOutOfRange.selector, 1.02e18, 1.01e18
            )
        );
        diversifier.swap(100e18);
    }

    function test_swapWithPriceGuardRevertsWhenSpotEmaDeviationTooWide() public {
        MockCurveStableSwapPool usdcPool = new MockCurveStableSwapPool(asset, usdc);
        usdcPool.setRawPrices(1.02e18, 1e18);
        usdc.mint(address(usdcPool), 1_000_000e6);
        asset.mint(address(treasury), 100e18);

        TreasuryStableDiversification.Target[] memory targets = new TreasuryStableDiversification.Target[](1);
        targets[0] = TreasuryStableDiversification.Target({
            token: address(usdc),
            weight: 1,
            swapPool: address(usdcPool),
            vault: address(0),
            inputToken: address(0),
            stakedAsset: address(0),
            maxPrice: 1.05e18,
            maxSpotEmaDeviationBps: 100,
            executionBufferBps: 100
        });
        vm.prank(address(core));
        diversifier.setTargets(targets);

        vm.expectRevert(
            abi.encodeWithSelector(
                TreasuryStableDiversification.TreasuryStableDiversification_OracleVolatile.selector, 1e18, 1.02e18, 100
            )
        );
        diversifier.swap(100e18);
    }

    function test_swapWithPriceGuardRevertsWhenExecutionBufferMinOutMissed() public {
        MockCurveStableSwapPool usdcPool = new MockCurveStableSwapPool(asset, usdc);
        usdcPool.setOutputBps(9_800);
        usdcPool.setEnforceMinOut(false);
        usdc.mint(address(usdcPool), 1_000_000e6);
        asset.mint(address(treasury), 100e18);

        TreasuryStableDiversification.Target[] memory targets = new TreasuryStableDiversification.Target[](1);
        targets[0] = TreasuryStableDiversification.Target({
            token: address(usdc),
            weight: 1,
            swapPool: address(usdcPool),
            vault: address(0),
            inputToken: address(0),
            stakedAsset: address(0),
            maxPrice: 1e18,
            maxSpotEmaDeviationBps: 100,
            executionBufferBps: 100
        });
        vm.prank(address(core));
        diversifier.setTargets(targets);

        vm.expectRevert(
            abi.encodeWithSelector(
                TreasuryStableDiversification.TreasuryStableDiversification_InsufficientOutput.selector,
                address(usdc),
                99e6,
                98e6
            )
        );
        diversifier.swap(100e18);
    }

    function test_swapDepositsTargetIntoVaultForTreasury() public {
        MockCurveStableSwapPool daiPool = new MockCurveStableSwapPool(asset, dai);
        MockDiversificationVault vault = new MockDiversificationVault(IERC20(address(dai)));
        dai.mint(address(daiPool), 1_000_000e18);
        asset.mint(address(treasury), 100e18);

        TreasuryStableDiversification.Target[] memory targets = new TreasuryStableDiversification.Target[](1);
        targets[0] = TreasuryStableDiversification.Target({
            token: address(dai),
            weight: 1,
            swapPool: address(daiPool),
            vault: address(vault),
            inputToken: address(0),
            stakedAsset: address(0),
            maxPrice: 0,
            maxSpotEmaDeviationBps: 0,
            executionBufferBps: 0
        });
        vm.prank(address(core));
        diversifier.setTargets(targets);

        diversifier.swap(100e18);

        assertEq(dai.balanceOf(address(treasury)), 0);
        assertEq(vault.balanceOf(address(treasury)), 100e18);
        assertEq(vault.totalAssets(), 100e18);
        assertEq(dai.balanceOf(address(diversifier)), 0);
    }

    function test_coreCanRetrieveStrayTokens() public {
        usdc.mint(address(diversifier), 123e6);

        core.execute(address(diversifier), abi.encodeCall(diversifier.retrieveToken, (address(usdc), recipient)));

        assertEq(usdc.balanceOf(recipient), 123e6);
        assertEq(usdc.balanceOf(address(diversifier)), 0);
    }
}

contract TreasuryStableDiversificationMainnetForkTest is Test {
    uint256 internal constant FULL_BPS = 10_000;
    uint256 internal constant MAX_DEVIATION_BPS = 4;
    uint16 internal constant EXECUTION_BUFFER_BPS = 4;
    uint256 internal constant MAX_PRICE = 1.001e18;

    address internal constant CRVUSD = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
    address internal constant SCRVUSD = 0x0655977FEb2f289A4aB78af67BAB0d17aAb84367;
    address internal constant SDOLA = 0xb45ad160634c528Cc3D2926d9807104FA3157305;
    address internal constant SDOLA_SCRVUSD_POOL = 0x76A962BA6770068bCF454D34dDE17175611e6637;
    address internal constant FRXUSD = 0xCAcd6fd266aF91b8AeD52aCCc382b4e165586E29;
    address internal constant SFRXUSD = 0xcf62F905562626CfcDD2261162a51fd02Fc9c5b6;
    address internal constant CRVUSD_FRXUSD_POOL = 0x13e12BB0E6A2f1A3d6901a59a9d585e89A6243e1;
    address internal constant FRXUSD_SFRXUSD_POOL = 0xF292eB6c5dcb693Eaaf392D0562a01C3710E5978;

    string internal mainnetRpcUrl;

    function setUp() public {
        mainnetRpcUrl = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(mainnetRpcUrl).length == 0) mainnetRpcUrl = vm.envOr("ETH_RPC_URL", string(""));
        if (bytes(mainnetRpcUrl).length == 0) mainnetRpcUrl = vm.envOr("MAINNET_URL", string(""));
        if (bytes(mainnetRpcUrl).length != 0) vm.createSelectFork(mainnetRpcUrl);
    }

    function test_liveStableDiversificationRoutesCrvUsdToSdolaAndSfrxUsd() public forkConfigured {
        Core core = new Core(address(this), 7 days);
        Treasury treasury = new Treasury(address(core));
        TreasuryStableDiversification diversifier =
            new TreasuryStableDiversification(address(core), address(treasury), CRVUSD, uint16(MAX_DEVIATION_BPS));
        core.execute(
            address(treasury),
            abi.encodeCall(Treasury.setTokenApproval, (CRVUSD, address(diversifier), type(uint256).max))
        );

        uint256 amount = 100e18;
        deal(CRVUSD, address(treasury), amount);

        TreasuryStableDiversification.Target[] memory targets = new TreasuryStableDiversification.Target[](3);
        targets[0] = TreasuryStableDiversification.Target({
            token: SDOLA,
            weight: 25,
            swapPool: SDOLA_SCRVUSD_POOL,
            vault: address(0),
            inputToken: address(0),
            stakedAsset: SCRVUSD,
            maxPrice: 0,
            maxSpotEmaDeviationBps: uint16(MAX_DEVIATION_BPS),
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
            maxSpotEmaDeviationBps: uint16(MAX_DEVIATION_BPS),
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
            maxSpotEmaDeviationBps: uint16(MAX_DEVIATION_BPS),
            executionBufferBps: EXECUTION_BUFFER_BPS
        });
        vm.prank(address(core));
        diversifier.setTargets(targets);

        uint256[] memory sdolaScrvRates = ICurvePoolView(SDOLA_SCRVUSD_POOL).stored_rates();
        assertApproxEqAbs(sdolaScrvRates[0], IERC4626(SCRVUSD).convertToAssets(1e18), 1);
        assertApproxEqAbs(sdolaScrvRates[1], IERC4626(SDOLA).convertToAssets(1e18), 1);

        uint256[] memory sfrxUsdRates = ICurvePoolView(FRXUSD_SFRXUSD_POOL).stored_rates();
        assertApproxEqAbs(sfrxUsdRates[0], IERC4626(SFRXUSD).convertToAssets(1e18), 1);
        assertEq(sfrxUsdRates[1], 1e18);

        uint256 sdolaSourceAssets = amount * targets[0].weight / diversifier.totalWeight();
        uint256 expectedScrvUsdShares = IERC4626(SCRVUSD).convertToShares(sdolaSourceAssets);
        uint256 expectedScrvUsdAssets = IERC4626(SCRVUSD).convertToAssets(expectedScrvUsdShares);
        uint256 expectedSdolaShares = ICurvePoolView(SDOLA_SCRVUSD_POOL).get_dy(0, 1, expectedScrvUsdShares);
        uint256 minSdolaShares = IERC4626(SDOLA).convertToShares(expectedScrvUsdAssets)
            * (FULL_BPS - MAX_DEVIATION_BPS) / FULL_BPS;

        uint256 sfrxUsdSourceAssets = amount * targets[1].weight / diversifier.totalWeight();
        uint256 expectedFrxUsd = ICurvePoolView(CRVUSD_FRXUSD_POOL).get_dy(1, 0, sfrxUsdSourceAssets);
        uint256 expectedSfrxUsdShares = ICurvePoolView(FRXUSD_SFRXUSD_POOL).get_dy(1, 0, expectedFrxUsd);
        uint256 minSfrxUsdShares = IERC4626(SFRXUSD).convertToShares(expectedFrxUsd * 1e18 / MAX_PRICE)
            * (FULL_BPS - EXECUTION_BUFFER_BPS) / FULL_BPS;

        uint256 assetAmount = diversifier.swap(amount);

        assertEq(assetAmount, amount);
        assertEq(IERC20(CRVUSD).balanceOf(address(treasury)), 0);
        assertEq(IERC20(CRVUSD).balanceOf(address(diversifier)), 0);
        assertEq(IERC20(SCRVUSD).balanceOf(address(diversifier)), 0);
        assertEq(IERC20(FRXUSD).balanceOf(address(treasury)), 0);
        assertEq(IERC20(FRXUSD).balanceOf(address(diversifier)), 0);
        assertEq(IERC20(SDOLA).balanceOf(address(diversifier)), 0);
        assertEq(IERC20(SFRXUSD).balanceOf(address(diversifier)), 0);
        assertGt(IERC20(SDOLA).balanceOf(address(treasury)), 0);
        assertGt(IERC20(SFRXUSD).balanceOf(address(treasury)), 0);

        uint256 sdolaShares = IERC20(SDOLA).balanceOf(address(treasury));
        uint256 sfrxUsdShares = IERC20(SFRXUSD).balanceOf(address(treasury));
        assertApproxEqAbs(sdolaShares, expectedSdolaShares, 1);
        assertApproxEqAbs(sfrxUsdShares, expectedSfrxUsdShares, 1);
        assertGe(sdolaShares, minSdolaShares);
        assertGe(sfrxUsdShares, minSfrxUsdShares);

        uint256 sdolaAssets = IERC4626(SDOLA).convertToAssets(sdolaShares);
        uint256 sfrxUsdAssets = IERC4626(SFRXUSD).convertToAssets(sfrxUsdShares);
        assertGe(sdolaAssets, IERC4626(SDOLA).convertToAssets(minSdolaShares));
        assertGe(sfrxUsdAssets, IERC4626(SFRXUSD).convertToAssets(minSfrxUsdShares));
    }

    modifier forkConfigured() {
        if (bytes(mainnetRpcUrl).length == 0) vm.skip(true);
        _;
    }
}
