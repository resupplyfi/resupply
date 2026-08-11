// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Setup } from "test/integration/Setup.sol";
import { RedemptionOperator } from "src/dao/operators/RedemptionOperator.sol";
import { BaseUpgradeableOperator } from "src/dao/operators/BaseUpgradeableOperator.sol";
import { UpgradeOperator } from "src/dao/operators/UpgradeOperator.sol";
import { IUpgradeableOperator } from "src/interfaces/IUpgradeableOperator.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IRedemptionHandler } from "src/interfaces/IRedemptionHandler.sol";
import { IRedemptionOperatorKeeper } from "src/interfaces/IRedemptionOperatorKeeper.sol";
import { IERC4626 } from "src/interfaces/IERC4626.sol";
import { ICurveExchange } from "src/interfaces/curve/ICurveExchange.sol";
import { IFrxUsd } from "src/interfaces/frax/IFrxUsd.sol";
import { IAuthHook } from "src/interfaces/IAuthHook.sol";
import { IMorpho } from "src/interfaces/IMorpho.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC3156FlashLender } from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { Upgrades } from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import { Options } from "@openzeppelin/foundry-upgrades/Options.sol";
import { Protocol, Mainnet } from "src/Constants.sol";

contract RedemptionVaultMock {
    function maxRedeem(address) external pure returns (uint256) {
        return type(uint256).max;
    }
}

contract RedemptionPairMock {
    address public immutable underlying;
    address public immutable collateral;

    constructor(address _underlying, address _collateral) {
        underlying = _underlying;
        collateral = _collateral;
    }

    function minimumRedemption() external pure returns (uint256) {
        return 100e18;
    }
}

contract RedemptionHandlerMock {
    using SafeERC20 for IERC20;

    IERC20 public immutable reusd;
    IERC20 public immutable underlying;

    constructor(address _reusd, address _underlying) {
        reusd = IERC20(_reusd);
        underlying = IERC20(_underlying);
    }

    function previewRedeem(address, uint256 amount) external pure returns (uint256 underlyingOut, uint256 collateralShares, uint256 fee) {
        return (amount * 110 / 100, amount, 1e16);
    }

    function redeemFromPair(address, uint256 amount, uint256, address receiver, bool) external returns (uint256 underlyingOut) {
        reusd.safeTransferFrom(msg.sender, address(this), amount);
        underlyingOut = amount * 110 / 100;
        underlying.safeTransfer(receiver, underlyingOut);
    }
}

/// @dev Frozen storage-bearing surface of the production implementation.
contract RedemptionOperatorV1Storage is BaseUpgradeableOperator, ReentrancyGuardUpgradeable {
    mapping(address => bool) public approvedCallers;
    address public manager;
}

contract RedemptionOperatorTest is Setup {
    using SafeERC20 for IERC20;

    uint256 internal constant FORK_BLOCK = 25_726_592;
    uint8 internal constant ROUTE_NONE = 0;
    uint8 internal constant ROUTE_CRVUSD_TO_CRVUSD = 1;
    uint8 internal constant ROUTE_CRVUSD_TO_FRXUSD = 2;
    uint8 internal constant ROUTE_USDC_TO_FRXUSD = 3;
    bytes32 internal constant REENTRANCY_GUARD_SLOT = 0x9b779b17422d0df92223018b32b4d1fa46e071723d6817e2486d003becc55f00;
    bytes32 internal constant ACTIVE_CALLBACK_HASH_SLOT = bytes32(uint256(2));
    string internal constant STORAGE_REFERENCE = "RedemptionOperator.t.sol:RedemptionOperatorV1Storage";

    struct CallbackDataFixture {
        address caller;
        address pair;
        uint8 routeId;
        uint256 loanAmount;
        uint256 minReusdFromSwap;
        uint256 minProfit;
        uint256 maxFeePct;
    }

    struct KeeperQuote {
        address pair;
        uint256 expectedProfit;
        uint256 redeemAmount;
        uint8 routeId;
        address loanAsset;
        uint256 loanAmount;
    }

    RedemptionOperator public redemptionOperator;
    IRedemptionOperatorKeeper public keeper;
    address public bot = address(0xB0B);

    event RedemptionExecuted(address indexed caller, address indexed pair, uint8 indexed routeId, address loanAsset, uint256 loanAmount, uint256 reusdAmount, uint256 profit);

    function setUp() public override {
        super.setUp();
        vm.createSelectFork(vm.envString("MAINNET_URL"), FORK_BLOCK);
        _deployRedemptionOperator();
    }

    function _deployRedemptionOperator() internal {
        address[] memory initialApproved = new address[](1);
        initialApproved[0] = bot;
        bytes memory initializerData = abi.encodeCall(RedemptionOperator.initialize, (Protocol.DEPLOYER, initialApproved));
        Options memory options;
        options.unsafeSkipAllChecks = true;
        address proxy = Upgrades.deployUUPSProxy("RedemptionOperator.sol:RedemptionOperator", initializerData, options);
        redemptionOperator = RedemptionOperator(proxy);
        keeper = IRedemptionOperatorKeeper(proxy);

        vm.prank(address(core));
        registry.setAddress("REDEMPTION_OPERATOR", proxy);
    }

    function test_IsProfitable_Zero() public {
        KeeperQuote memory quote = _quote(0);
        _assertNoQuote(quote);
    }

    function test_KeeperAbiSelectorsAndOutputOrder() public view {
        assertEq(IRedemptionOperatorKeeper.isProfitable.selector, bytes4(0x243976cc), "quote selector");
        assertEq(IRedemptionOperatorKeeper.executeRedemption.selector, bytes4(0x4d58ad8a), "execution selector");

        (bool success, bytes memory result) = address(keeper).staticcall(abi.encodeWithSelector(IRedemptionOperatorKeeper.isProfitable.selector, 0));
        assertTrue(success);
        (address pair, uint256 expectedProfit, uint256 redeemAmount, uint8 routeId, address loanAsset, uint256 loanAmount) = abi.decode(result, (address, uint256, uint256, uint8, address, uint256));
        assertEq(pair, address(0));
        assertEq(expectedProfit, 0);
        assertEq(redeemAmount, 0);
        assertEq(routeId, ROUTE_NONE);
        assertEq(loanAsset, address(0));
        assertEq(loanAmount, 0);
    }

    function test_CrvUsdToCrvUsd_RoundTrip() public {
        RedemptionVaultMock vault = new RedemptionVaultMock();
        RedemptionPairMock pair = new RedemptionPairMock(Mainnet.CRVUSD_ERC20, address(vault));
        RedemptionHandlerMock handler = new RedemptionHandlerMock(address(stablecoin), Mainnet.CRVUSD_ERC20);

        vm.mockCall(address(registry), abi.encodeWithSelector(IResupplyRegistry.redemptionHandler.selector), abi.encode(address(handler)));
        address[] memory onlyPair = new address[](1);
        onlyPair[0] = address(pair);
        vm.mockCall(address(registry), abi.encodeWithSelector(IResupplyRegistry.getAllPairAddresses.selector), abi.encode(onlyPair));
        _deployRedemptionOperator();
        deal(Mainnet.CRVUSD_ERC20, address(handler), 1_000_000e18);
        (address[6] memory dustTokens, uint256[6] memory dust) = _seedOperatorDust();

        uint256 notionalWad = 10_000e18;
        KeeperQuote memory quote = _quote(notionalWad);
        assertEq(quote.pair, address(pair));
        assertEq(quote.routeId, ROUTE_CRVUSD_TO_CRVUSD);
        assertEq(quote.loanAsset, redemptionOperator.crvUsd());
        assertEq(quote.loanAmount, notionalWad);
        assertGt(quote.expectedProfit, 0);

        uint256 treasuryBefore = IERC20(Mainnet.CRVUSD_ERC20).balanceOf(Protocol.TREASURY);
        vm.expectEmit(true, true, true, true, address(redemptionOperator));
        emit RedemptionExecuted(bot, quote.pair, quote.routeId, quote.loanAsset, quote.loanAmount, quote.redeemAmount, quote.expectedProfit);
        vm.prank(bot);
        keeper.executeRedemption(quote.pair, quote.routeId, quote.loanAmount, quote.redeemAmount * 9980 / 10_000, quote.expectedProfit / 2, type(uint256).max);
        uint256 treasuryAfter = IERC20(Mainnet.CRVUSD_ERC20).balanceOf(Protocol.TREASURY);
        assertGt(treasuryAfter - treasuryBefore, 0, "profit not recorded");
        _assertOperatorDust(dustTokens, dust);
    }

    function test_CrvUsdToFrxUsd_HistoricalReplay() public {
        address expectedPair = _findPair(Mainnet.FRXUSD_ERC20);
        address[] memory onlyPair = new address[](1);
        onlyPair[0] = expectedPair;
        vm.mockCall(address(registry), abi.encodeWithSelector(IResupplyRegistry.getAllPairAddresses.selector), abi.encode(onlyPair));
        deal(redemptionOperator.usdc(), redemptionOperator.morpho(), 0);

        KeeperQuote memory quote = _findCrvReplay(expectedPair, redemptionOperator.reusdSfrxPool(), 500_000e18);
        assertGt(quote.loanAmount, 0);
        assertEq(quote.routeId, ROUTE_CRVUSD_TO_FRXUSD);
        assertEq(quote.loanAsset, redemptionOperator.crvUsd());
        (address[6] memory dustTokens, uint256[6] memory dust) = _seedOperatorDust();

        uint256 treasuryBefore = IERC20(Mainnet.CRVUSD_ERC20).balanceOf(Protocol.TREASURY);
        vm.prank(bot);
        keeper.executeRedemption(quote.pair, quote.routeId, quote.loanAmount, quote.redeemAmount * 9980 / 10_000, quote.expectedProfit / 2, type(uint256).max);
        assertGe(IERC20(Mainnet.CRVUSD_ERC20).balanceOf(Protocol.TREASURY) - treasuryBefore, quote.expectedProfit / 2);
        _assertOperatorDust(dustTokens, dust);
    }

    function test_IsProfitable_UsdcReturnsNativeLoanUnits() public {
        _disableCrvUsdFunding();
        KeeperQuote memory quote = _quote(10_000e18);
        assertNotEq(quote.pair, address(0));
        assertGt(quote.expectedProfit, 0);
        assertGt(quote.redeemAmount, 0);
        assertEq(quote.routeId, ROUTE_USDC_TO_FRXUSD);
        assertEq(quote.loanAsset, redemptionOperator.usdc());
        assertEq(quote.loanAmount, 10_000e6);
        assertEq(IResupplyPair(quote.pair).underlying(), Mainnet.FRXUSD_ERC20);

        (uint256 underlyingOut, uint256 collateralShares, uint256 fee) = IRedemptionHandler(address(redemptionHandler)).previewRedeem(quote.pair, quote.redeemAmount);
        assertGt(underlyingOut, 0);
        assertGt(collateralShares, 0);
        assertGt(fee, 0);
        assertLe(collateralShares, IERC4626(IResupplyPair(quote.pair).collateral()).maxRedeem(quote.pair));
    }

    function test_IsProfitable_UsdcRequiresMorphoLiquidity() public {
        _disableCrvUsdFunding();
        uint256 notionalWad = 10_000e18;
        deal(redemptionOperator.usdc(), redemptionOperator.morpho(), 10_000e6 - 1);

        _assertNoQuote(_quote(notionalWad));
    }

    function test_IsProfitable_UsdcRespectsCustodianCap() public {
        _disableCrvUsdFunding();
        uint256 notionalWad = 10_000e18;
        uint256 usdcLoanAmount = 10_000e6;
        vm.mockCall(redemptionOperator.frxUsdCustodian(), abi.encodeCall(IERC4626.maxDeposit, (address(redemptionOperator))), abi.encode(usdcLoanAmount - 1));

        _assertNoQuote(_quote(notionalWad));
    }

    function test_IsProfitable_FrxUsdPauseFallsBackToCrvUsdRoute() public {
        uint256 notionalWad = 10_000e18;
        uint256 redeemAmount = 10_000e18;
        uint256 underlyingAmount = 11_000e18;

        RedemptionVaultMock vault = new RedemptionVaultMock();
        RedemptionPairMock crvPair = new RedemptionPairMock(Mainnet.CRVUSD_ERC20, address(vault));
        RedemptionPairMock frxPair = new RedemptionPairMock(Mainnet.FRXUSD_ERC20, address(vault));
        RedemptionHandlerMock handler = new RedemptionHandlerMock(address(stablecoin), Mainnet.CRVUSD_ERC20);
        address[] memory pairs = new address[](2);
        pairs[0] = address(crvPair);
        pairs[1] = address(frxPair);

        vm.mockCall(address(registry), abi.encodeWithSelector(IResupplyRegistry.redemptionHandler.selector), abi.encode(address(handler)));
        vm.mockCall(address(registry), abi.encodeWithSelector(IResupplyRegistry.getAllPairAddresses.selector), abi.encode(pairs));
        vm.mockCall(redemptionOperator.frxUsd(), abi.encodeCall(IFrxUsd.isPaused, ()), abi.encode(true));
        _mockCrvUsdFunding(notionalWad, 0);
        vm.mockCall(redemptionOperator.sCrvUsd(), abi.encodeCall(IERC4626.previewDeposit, (notionalWad)), abi.encode(notionalWad));
        vm.mockCall(redemptionOperator.reusdScrvPool(), abi.encodeCall(ICurveExchange.get_dy, (redemptionOperator.scrvIndex(), redemptionOperator.reusdIndexScrv(), notionalWad)), abi.encode(redeemAmount));
        vm.mockCall(redemptionOperator.crvUsdFrxUsdPool(), abi.encodeCall(ICurveExchange.get_dy, (redemptionOperator.crvUsdIndexFrxPool(), redemptionOperator.frxUsdIndexFrxPool(), notionalWad)), abi.encode(redeemAmount));
        vm.mockCall(redemptionOperator.frxusdSfrxusdPool(), abi.encodeCall(ICurveExchange.get_dy, (redemptionOperator.frxusdIndexFraxPool(), redemptionOperator.sfrxusdIndexFraxPool(), redeemAmount)), abi.encode(redeemAmount));
        vm.mockCall(redemptionOperator.reusdSfrxPool(), abi.encodeCall(ICurveExchange.get_dy, (redemptionOperator.sfrxIndex(), redemptionOperator.reusdIndexSfrx(), redeemAmount)), abi.encode(redeemAmount));
        vm.mockCall(redemptionOperator.crvUsdFrxUsdPool(), abi.encodeCall(ICurveExchange.get_dy, (redemptionOperator.frxUsdIndexFrxPool(), redemptionOperator.crvUsdIndexFrxPool(), underlyingAmount)), abi.encode(notionalWad + 2000e18));
        deal(redemptionOperator.usdc(), redemptionOperator.morpho(), 0);

        KeeperQuote memory quote = _quote(notionalWad);
        assertEq(quote.pair, address(crvPair));
        assertEq(quote.routeId, ROUTE_CRVUSD_TO_CRVUSD);
        assertEq(quote.expectedProfit, 1000e18);
    }

    function test_IsProfitable_DisabledCustodianMinterFallsBackToCrvUsdRoute() public {
        uint256 notionalWad = 10_000e18;
        uint256 usdcLoanAmount = 10_000e6;
        uint256 crvAcquiredFrxUsd = 10_000e18;
        uint256 usdcAcquiredFrxUsd = 12_000e18;
        uint256 crvUnderlyingAmount = 11_000e18;
        uint256 usdcUnderlyingAmount = 13_200e18;
        uint256 frxUsdForRepayment = 10_000e18;

        RedemptionVaultMock vault = new RedemptionVaultMock();
        RedemptionPairMock pair = new RedemptionPairMock(Mainnet.FRXUSD_ERC20, address(vault));
        RedemptionHandlerMock handler = new RedemptionHandlerMock(address(stablecoin), Mainnet.FRXUSD_ERC20);
        address[] memory onlyPair = new address[](1);
        onlyPair[0] = address(pair);

        vm.mockCall(address(registry), abi.encodeWithSelector(IResupplyRegistry.redemptionHandler.selector), abi.encode(address(handler)));
        vm.mockCall(address(registry), abi.encodeWithSelector(IResupplyRegistry.getAllPairAddresses.selector), abi.encode(onlyPair));
        vm.mockCall(redemptionOperator.frxUsd(), abi.encodeCall(IFrxUsd.isPaused, ()), abi.encode(false));
        vm.mockCall(redemptionOperator.frxUsd(), abi.encodeCall(IFrxUsd.minters, (redemptionOperator.frxUsdCustodian())), abi.encode(false));
        _mockCrvUsdFunding(notionalWad, 0);
        vm.mockCall(redemptionOperator.crvUsdFrxUsdPool(), abi.encodeCall(ICurveExchange.get_dy, (redemptionOperator.crvUsdIndexFrxPool(), redemptionOperator.frxUsdIndexFrxPool(), notionalWad)), abi.encode(crvAcquiredFrxUsd));
        vm.mockCall(redemptionOperator.frxusdSfrxusdPool(), abi.encodeCall(ICurveExchange.get_dy, (redemptionOperator.frxusdIndexFraxPool(), redemptionOperator.sfrxusdIndexFraxPool(), crvAcquiredFrxUsd)), abi.encode(crvAcquiredFrxUsd));
        vm.mockCall(redemptionOperator.reusdSfrxPool(), abi.encodeCall(ICurveExchange.get_dy, (redemptionOperator.sfrxIndex(), redemptionOperator.reusdIndexSfrx(), crvAcquiredFrxUsd)), abi.encode(crvAcquiredFrxUsd));
        vm.mockCall(redemptionOperator.crvUsdFrxUsdPool(), abi.encodeCall(ICurveExchange.get_dy, (redemptionOperator.frxUsdIndexFrxPool(), redemptionOperator.crvUsdIndexFrxPool(), crvUnderlyingAmount)), abi.encode(notionalWad + 1500e18));

        deal(redemptionOperator.usdc(), redemptionOperator.morpho(), usdcLoanAmount);
        vm.mockCall(redemptionOperator.frxUsdCustodian(), abi.encodeCall(IERC4626.maxDeposit, (address(redemptionOperator))), abi.encode(type(uint256).max));
        vm.mockCall(redemptionOperator.frxUsdCustodian(), abi.encodeCall(IERC4626.previewDeposit, (usdcLoanAmount)), abi.encode(usdcAcquiredFrxUsd));
        vm.mockCall(redemptionOperator.frxUsdCustodian(), abi.encodeCall(IERC4626.previewWithdraw, (usdcLoanAmount)), abi.encode(frxUsdForRepayment));
        vm.mockCall(redemptionOperator.frxusdSfrxusdPool(), abi.encodeCall(ICurveExchange.get_dy, (redemptionOperator.frxusdIndexFraxPool(), redemptionOperator.sfrxusdIndexFraxPool(), usdcAcquiredFrxUsd)), abi.encode(usdcAcquiredFrxUsd));
        vm.mockCall(redemptionOperator.reusdSfrxPool(), abi.encodeCall(ICurveExchange.get_dy, (redemptionOperator.sfrxIndex(), redemptionOperator.reusdIndexSfrx(), usdcAcquiredFrxUsd)), abi.encode(usdcAcquiredFrxUsd));
        vm.mockCall(redemptionOperator.crvUsdFrxUsdPool(), abi.encodeCall(ICurveExchange.get_dy, (redemptionOperator.frxUsdIndexFrxPool(), redemptionOperator.crvUsdIndexFrxPool(), usdcUnderlyingAmount - frxUsdForRepayment)), abi.encode(3000e18));

        KeeperQuote memory quote = _quote(notionalWad);
        assertEq(quote.pair, address(pair));
        assertEq(quote.routeId, ROUTE_CRVUSD_TO_FRXUSD);
        assertEq(quote.expectedProfit, 1500e18);
    }

    function test_IsProfitable_UsdcUsesCustodianPreviewRounding() public {
        _disableCrvUsdFunding();
        uint256 notionalWad = 10_000e18 + 999_999_999_999;
        uint256 usdcLoanAmount = 10_000e6;
        uint256 frxMinted = 9999e18 + 7;
        uint256 sfrxOut = frxMinted - 13;
        uint256 reusdOut = sfrxOut - 17;
        uint256 underlyingOut = reusdOut * 110 / 100;
        uint256 frxForUsdc = 10_002e18 + 19;
        uint256 expectedProfit = 995e18;

        RedemptionVaultMock vault = new RedemptionVaultMock();
        RedemptionPairMock pair = new RedemptionPairMock(Mainnet.FRXUSD_ERC20, address(vault));
        RedemptionHandlerMock handler = new RedemptionHandlerMock(address(stablecoin), Mainnet.FRXUSD_ERC20);
        address[] memory onlyPair = new address[](1);
        onlyPair[0] = address(pair);

        vm.mockCall(address(registry), abi.encodeWithSelector(IResupplyRegistry.redemptionHandler.selector), abi.encode(address(handler)));
        vm.mockCall(address(registry), abi.encodeWithSelector(IResupplyRegistry.getAllPairAddresses.selector), abi.encode(onlyPair));
        vm.mockCall(redemptionOperator.frxUsdCustodian(), abi.encodeCall(IERC4626.maxDeposit, (address(redemptionOperator))), abi.encode(type(uint256).max));
        vm.mockCall(redemptionOperator.frxUsdCustodian(), abi.encodeCall(IERC4626.previewDeposit, (usdcLoanAmount)), abi.encode(frxMinted));
        vm.mockCall(redemptionOperator.frxUsdCustodian(), abi.encodeCall(IERC4626.previewWithdraw, (usdcLoanAmount)), abi.encode(frxForUsdc));
        vm.mockCall(redemptionOperator.frxusdSfrxusdPool(), abi.encodeCall(ICurveExchange.get_dy, (redemptionOperator.frxusdIndexFraxPool(), redemptionOperator.sfrxusdIndexFraxPool(), frxMinted)), abi.encode(sfrxOut));
        vm.mockCall(redemptionOperator.reusdSfrxPool(), abi.encodeCall(ICurveExchange.get_dy, (redemptionOperator.sfrxIndex(), redemptionOperator.reusdIndexSfrx(), sfrxOut)), abi.encode(reusdOut));
        vm.mockCall(redemptionOperator.crvUsdFrxUsdPool(), abi.encodeCall(ICurveExchange.get_dy, (redemptionOperator.frxUsdIndexFrxPool(), redemptionOperator.crvUsdIndexFrxPool(), underlyingOut - frxForUsdc)), abi.encode(expectedProfit));

        KeeperQuote memory quote = _quote(notionalWad);
        assertEq(quote.pair, address(pair));
        assertEq(quote.expectedProfit, expectedProfit);
        assertEq(quote.redeemAmount, reusdOut);
        assertEq(quote.routeId, ROUTE_USDC_TO_FRXUSD);
        assertEq(quote.loanAsset, redemptionOperator.usdc());
        assertEq(quote.loanAmount, usdcLoanAmount, "USDC conversion must round down");
    }

    function test_IsProfitable_UsdcZeroNativeAmountIsUnavailable() public {
        _disableCrvUsdFunding();
        _assertNoQuote(_quote(1e12 - 1));
    }

    function test_IsProfitable_CrossRouteTieUsesLowerRouteId() public {
        uint256 notionalWad = 10_000e18;
        uint256 usdcLoanAmount = 10_000e6;
        uint256 acquiredFrxUsd = 10_000e18;
        uint256 acquiredSFrxUsd = 10_000e18;
        uint256 redeemAmount = 10_000e18;
        uint256 underlyingAmount = 11_000e18;
        uint256 frxUsdForUsdc = 9000e18;
        uint256 tiedProfit = 1000e18;

        RedemptionVaultMock vault = new RedemptionVaultMock();
        RedemptionPairMock pair = new RedemptionPairMock(Mainnet.FRXUSD_ERC20, address(vault));
        RedemptionHandlerMock handler = new RedemptionHandlerMock(address(stablecoin), Mainnet.FRXUSD_ERC20);
        address[] memory onlyPair = new address[](1);
        onlyPair[0] = address(pair);
        vm.mockCall(address(registry), abi.encodeWithSelector(IResupplyRegistry.redemptionHandler.selector), abi.encode(address(handler)));
        vm.mockCall(address(registry), abi.encodeWithSelector(IResupplyRegistry.getAllPairAddresses.selector), abi.encode(onlyPair));

        _mockCrvUsdFunding(notionalWad, 0);
        vm.mockCall(redemptionOperator.sCrvUsd(), abi.encodeCall(IERC4626.previewDeposit, (notionalWad)), abi.encode(0));
        vm.mockCall(redemptionOperator.crvUsdFrxUsdPool(), abi.encodeCall(ICurveExchange.get_dy, (redemptionOperator.crvUsdIndexFrxPool(), redemptionOperator.frxUsdIndexFrxPool(), notionalWad)), abi.encode(acquiredFrxUsd));

        deal(redemptionOperator.usdc(), redemptionOperator.morpho(), usdcLoanAmount);
        vm.mockCall(redemptionOperator.frxUsdCustodian(), abi.encodeCall(IERC4626.maxDeposit, (address(redemptionOperator))), abi.encode(type(uint256).max));
        vm.mockCall(redemptionOperator.frxUsdCustodian(), abi.encodeCall(IERC4626.previewDeposit, (usdcLoanAmount)), abi.encode(acquiredFrxUsd));
        vm.mockCall(redemptionOperator.frxUsdCustodian(), abi.encodeCall(IERC4626.previewWithdraw, (usdcLoanAmount)), abi.encode(frxUsdForUsdc));
        vm.mockCall(redemptionOperator.frxusdSfrxusdPool(), abi.encodeCall(ICurveExchange.get_dy, (redemptionOperator.frxusdIndexFraxPool(), redemptionOperator.sfrxusdIndexFraxPool(), acquiredFrxUsd)), abi.encode(acquiredSFrxUsd));
        vm.mockCall(redemptionOperator.reusdSfrxPool(), abi.encodeCall(ICurveExchange.get_dy, (redemptionOperator.sfrxIndex(), redemptionOperator.reusdIndexSfrx(), acquiredSFrxUsd)), abi.encode(redeemAmount));
        vm.mockCall(redemptionOperator.crvUsdFrxUsdPool(), abi.encodeCall(ICurveExchange.get_dy, (redemptionOperator.frxUsdIndexFrxPool(), redemptionOperator.crvUsdIndexFrxPool(), underlyingAmount)), abi.encode(notionalWad + tiedProfit));
        vm.mockCall(redemptionOperator.crvUsdFrxUsdPool(), abi.encodeCall(ICurveExchange.get_dy, (redemptionOperator.frxUsdIndexFrxPool(), redemptionOperator.crvUsdIndexFrxPool(), underlyingAmount - frxUsdForUsdc)), abi.encode(tiedProfit));

        KeeperQuote memory quote = _quote(notionalWad);
        assertEq(quote.pair, address(pair));
        assertEq(quote.expectedProfit, tiedProfit);
        assertEq(quote.routeId, ROUTE_CRVUSD_TO_FRXUSD);
        assertEq(quote.loanAsset, redemptionOperator.crvUsd());
        assertEq(quote.loanAmount, notionalWad);
    }

    function test_IsProfitable_WithinRouteTieKeepsFirstRegistryPair() public {
        uint256 notionalWad = 10_000e18;
        uint256 redeemAmount = 10_000e18;
        RedemptionVaultMock vault = new RedemptionVaultMock();
        RedemptionPairMock firstPair = new RedemptionPairMock(Mainnet.CRVUSD_ERC20, address(vault));
        RedemptionPairMock secondPair = new RedemptionPairMock(Mainnet.CRVUSD_ERC20, address(vault));
        RedemptionHandlerMock handler = new RedemptionHandlerMock(address(stablecoin), Mainnet.CRVUSD_ERC20);
        address[] memory pairs = new address[](2);
        pairs[0] = address(firstPair);
        pairs[1] = address(secondPair);
        vm.mockCall(address(registry), abi.encodeWithSelector(IResupplyRegistry.redemptionHandler.selector), abi.encode(address(handler)));
        vm.mockCall(address(registry), abi.encodeWithSelector(IResupplyRegistry.getAllPairAddresses.selector), abi.encode(pairs));

        _mockCrvUsdFunding(notionalWad, 0);
        vm.mockCall(redemptionOperator.sCrvUsd(), abi.encodeCall(IERC4626.previewDeposit, (notionalWad)), abi.encode(notionalWad));
        vm.mockCall(redemptionOperator.reusdScrvPool(), abi.encodeCall(ICurveExchange.get_dy, (redemptionOperator.scrvIndex(), redemptionOperator.reusdIndexScrv(), notionalWad)), abi.encode(redeemAmount));
        vm.mockCall(redemptionOperator.crvUsdFrxUsdPool(), abi.encodeCall(ICurveExchange.get_dy, (redemptionOperator.crvUsdIndexFrxPool(), redemptionOperator.frxUsdIndexFrxPool(), notionalWad)), abi.encode(0));
        deal(redemptionOperator.usdc(), redemptionOperator.morpho(), 0);

        KeeperQuote memory quote = _quote(notionalWad);
        assertEq(quote.pair, address(firstPair));
        assertEq(quote.routeId, ROUTE_CRVUSD_TO_CRVUSD);
        assertEq(quote.expectedProfit, 1000e18);
    }

    function test_IsProfitable_ZeroAcquisitionOnlyDisablesAffectedRoute() public {
        uint256 notionalWad = 10_000e18;
        uint256 usdcLoanAmount = 10_000e6;
        _disableCrvUsdFunding();
        deal(redemptionOperator.usdc(), redemptionOperator.morpho(), usdcLoanAmount);
        vm.mockCall(redemptionOperator.frxUsdCustodian(), abi.encodeCall(IERC4626.maxDeposit, (address(redemptionOperator))), abi.encode(type(uint256).max));
        vm.mockCall(redemptionOperator.frxUsdCustodian(), abi.encodeCall(IERC4626.previewDeposit, (usdcLoanAmount)), abi.encode(0));

        _assertNoQuote(_quote(notionalWad));
    }

    function test_IsProfitable_ZeroDebtPairFallsBackToNextPair() public {
        uint256 notionalWad = 10_000e18;
        uint256 redeemAmount = 10_000e18;
        RedemptionVaultMock vault = new RedemptionVaultMock();
        RedemptionPairMock emptyPair = new RedemptionPairMock(Mainnet.CRVUSD_ERC20, address(vault));
        RedemptionPairMock fallbackPair = new RedemptionPairMock(Mainnet.CRVUSD_ERC20, address(vault));
        RedemptionHandlerMock handler = new RedemptionHandlerMock(address(stablecoin), Mainnet.CRVUSD_ERC20);
        address[] memory pairs = new address[](2);
        pairs[0] = address(emptyPair);
        pairs[1] = address(fallbackPair);

        vm.mockCall(address(registry), abi.encodeWithSelector(IResupplyRegistry.redemptionHandler.selector), abi.encode(address(handler)));
        vm.mockCall(address(registry), abi.encodeWithSelector(IResupplyRegistry.getAllPairAddresses.selector), abi.encode(pairs));
        vm.mockCall(address(handler), abi.encodeCall(IRedemptionHandler.previewRedeem, (address(emptyPair), redeemAmount)), abi.encode(0, 0, 0));
        _mockOnlyCrvUsdToCrvUsdFunding(notionalWad, redeemAmount);

        KeeperQuote memory quote = _quote(notionalWad);
        assertEq(quote.pair, address(fallbackPair));
        assertEq(quote.routeId, ROUTE_CRVUSD_TO_CRVUSD);
        assertEq(quote.expectedProfit, 1000e18);
    }

    function test_IsProfitable_BelowMinimumPairFallsBackToNextPair() public {
        uint256 notionalWad = 10_000e18;
        uint256 redeemAmount = 10_000e18;
        RedemptionVaultMock vault = new RedemptionVaultMock();
        RedemptionPairMock belowMinimumPair = new RedemptionPairMock(Mainnet.CRVUSD_ERC20, address(vault));
        RedemptionPairMock fallbackPair = new RedemptionPairMock(Mainnet.CRVUSD_ERC20, address(vault));
        RedemptionHandlerMock handler = new RedemptionHandlerMock(address(stablecoin), Mainnet.CRVUSD_ERC20);
        address[] memory pairs = new address[](2);
        pairs[0] = address(belowMinimumPair);
        pairs[1] = address(fallbackPair);

        vm.mockCall(address(registry), abi.encodeWithSelector(IResupplyRegistry.redemptionHandler.selector), abi.encode(address(handler)));
        vm.mockCall(address(registry), abi.encodeWithSelector(IResupplyRegistry.getAllPairAddresses.selector), abi.encode(pairs));
        vm.mockCall(address(belowMinimumPair), abi.encodeWithSelector(IResupplyPair.minimumRedemption.selector), abi.encode(redeemAmount + 1));
        vm.mockCallRevert(address(handler), abi.encodeCall(IRedemptionHandler.previewRedeem, (address(belowMinimumPair), redeemAmount)), abi.encodeWithSignature("Error(string)", "preview should not be called"));
        _mockOnlyCrvUsdToCrvUsdFunding(notionalWad, redeemAmount);

        KeeperQuote memory quote = _quote(notionalWad);
        assertEq(quote.pair, address(fallbackPair));
        assertEq(quote.routeId, ROUTE_CRVUSD_TO_CRVUSD);
        assertEq(quote.expectedProfit, 1000e18);
    }

    function test_IsProfitable_CollateralCappedPairFallsBackToNextPair() public {
        uint256 notionalWad = 10_000e18;
        uint256 redeemAmount = 10_000e18;
        RedemptionVaultMock vault = new RedemptionVaultMock();
        RedemptionPairMock cappedPair = new RedemptionPairMock(Mainnet.CRVUSD_ERC20, address(vault));
        RedemptionPairMock fallbackPair = new RedemptionPairMock(Mainnet.CRVUSD_ERC20, address(vault));
        RedemptionHandlerMock handler = new RedemptionHandlerMock(address(stablecoin), Mainnet.CRVUSD_ERC20);
        address[] memory pairs = new address[](2);
        pairs[0] = address(cappedPair);
        pairs[1] = address(fallbackPair);

        vm.mockCall(address(registry), abi.encodeWithSelector(IResupplyRegistry.redemptionHandler.selector), abi.encode(address(handler)));
        vm.mockCall(address(registry), abi.encodeWithSelector(IResupplyRegistry.getAllPairAddresses.selector), abi.encode(pairs));
        vm.mockCall(address(vault), abi.encodeCall(IERC4626.maxRedeem, (address(cappedPair))), abi.encode(redeemAmount - 1));
        _mockOnlyCrvUsdToCrvUsdFunding(notionalWad, redeemAmount);

        KeeperQuote memory quote = _quote(notionalWad);
        assertEq(quote.pair, address(fallbackPair));
        assertEq(quote.routeId, ROUTE_CRVUSD_TO_CRVUSD);
        assertEq(quote.expectedProfit, 1000e18);
    }

    function test_IsProfitable_ZeroSettlementDisablesOnlyUsdcRoute() public {
        uint256 notionalWad = 10_000e18;
        uint256 usdcLoanAmount = 10_000e6;
        uint256 crvRedeemAmount = 10_000e18;
        uint256 usdcRedeemAmount = 12_000e18;
        uint256 crvUnderlyingAmount = crvRedeemAmount * 110 / 100;
        uint256 crvUsdProceeds = 11_500e18;

        RedemptionVaultMock vault = new RedemptionVaultMock();
        RedemptionPairMock pair = new RedemptionPairMock(Mainnet.FRXUSD_ERC20, address(vault));
        RedemptionHandlerMock handler = new RedemptionHandlerMock(address(stablecoin), Mainnet.FRXUSD_ERC20);
        address[] memory onlyPair = new address[](1);
        onlyPair[0] = address(pair);

        vm.mockCall(address(registry), abi.encodeWithSelector(IResupplyRegistry.redemptionHandler.selector), abi.encode(address(handler)));
        vm.mockCall(address(registry), abi.encodeWithSelector(IResupplyRegistry.getAllPairAddresses.selector), abi.encode(onlyPair));

        _mockCrvUsdFunding(notionalWad, 0);
        vm.mockCall(redemptionOperator.sCrvUsd(), abi.encodeCall(IERC4626.previewDeposit, (notionalWad)), abi.encode(0));
        vm.mockCall(redemptionOperator.crvUsdFrxUsdPool(), abi.encodeCall(ICurveExchange.get_dy, (redemptionOperator.crvUsdIndexFrxPool(), redemptionOperator.frxUsdIndexFrxPool(), notionalWad)), abi.encode(crvRedeemAmount));
        vm.mockCall(redemptionOperator.frxusdSfrxusdPool(), abi.encodeCall(ICurveExchange.get_dy, (redemptionOperator.frxusdIndexFraxPool(), redemptionOperator.sfrxusdIndexFraxPool(), crvRedeemAmount)), abi.encode(crvRedeemAmount));
        vm.mockCall(redemptionOperator.reusdSfrxPool(), abi.encodeCall(ICurveExchange.get_dy, (redemptionOperator.sfrxIndex(), redemptionOperator.reusdIndexSfrx(), crvRedeemAmount)), abi.encode(crvRedeemAmount));
        vm.mockCall(redemptionOperator.crvUsdFrxUsdPool(), abi.encodeCall(ICurveExchange.get_dy, (redemptionOperator.frxUsdIndexFrxPool(), redemptionOperator.crvUsdIndexFrxPool(), crvUnderlyingAmount)), abi.encode(crvUsdProceeds));

        deal(redemptionOperator.usdc(), redemptionOperator.morpho(), usdcLoanAmount);
        vm.mockCall(redemptionOperator.frxUsdCustodian(), abi.encodeCall(IERC4626.maxDeposit, (address(redemptionOperator))), abi.encode(type(uint256).max));
        vm.mockCall(redemptionOperator.frxUsdCustodian(), abi.encodeCall(IERC4626.previewDeposit, (usdcLoanAmount)), abi.encode(usdcRedeemAmount));
        vm.mockCall(redemptionOperator.frxusdSfrxusdPool(), abi.encodeCall(ICurveExchange.get_dy, (redemptionOperator.frxusdIndexFraxPool(), redemptionOperator.sfrxusdIndexFraxPool(), usdcRedeemAmount)), abi.encode(usdcRedeemAmount));
        vm.mockCall(redemptionOperator.reusdSfrxPool(), abi.encodeCall(ICurveExchange.get_dy, (redemptionOperator.sfrxIndex(), redemptionOperator.reusdIndexSfrx(), usdcRedeemAmount)), abi.encode(usdcRedeemAmount));
        vm.mockCall(redemptionOperator.frxUsdCustodian(), abi.encodeCall(IERC4626.previewWithdraw, (usdcLoanAmount)), abi.encode(0));

        KeeperQuote memory quote = _quote(notionalWad);
        assertEq(quote.pair, address(pair));
        assertEq(quote.routeId, ROUTE_CRVUSD_TO_FRXUSD);
        assertEq(quote.expectedProfit, crvUsdProceeds - notionalWad);
        assertEq(quote.redeemAmount, crvRedeemAmount);
    }

    function test_IsProfitable_UnexpectedHandlerFailureBubblesWithValidFallback() public {
        uint256 notionalWad = 10_000e18;
        uint256 redeemAmount = 10_000e18;
        RedemptionVaultMock vault = new RedemptionVaultMock();
        RedemptionPairMock revertingPair = new RedemptionPairMock(Mainnet.CRVUSD_ERC20, address(vault));
        RedemptionPairMock fallbackPair = new RedemptionPairMock(Mainnet.CRVUSD_ERC20, address(vault));
        RedemptionHandlerMock handler = new RedemptionHandlerMock(address(stablecoin), Mainnet.CRVUSD_ERC20);
        address[] memory pairs = new address[](2);
        pairs[0] = address(revertingPair);
        pairs[1] = address(fallbackPair);

        vm.mockCall(address(registry), abi.encodeWithSelector(IResupplyRegistry.redemptionHandler.selector), abi.encode(address(handler)));
        vm.mockCall(address(registry), abi.encodeWithSelector(IResupplyRegistry.getAllPairAddresses.selector), abi.encode(pairs));
        bytes memory failure = abi.encodeWithSignature("Error(string)", "handler failure");
        vm.mockCallRevert(address(handler), abi.encodeCall(IRedemptionHandler.previewRedeem, (address(revertingPair), redeemAmount)), failure);
        _mockOnlyCrvUsdToCrvUsdFunding(notionalWad, redeemAmount);

        vm.expectRevert(failure);
        keeper.isProfitable(notionalWad);
    }

    function test_IsProfitable_UnexpectedPoolFailureBubblesWithValidAlternative() public {
        uint256 notionalWad = 10_000e18;
        uint256 redeemAmount = 10_000e18;
        RedemptionVaultMock vault = new RedemptionVaultMock();
        RedemptionPairMock pair = new RedemptionPairMock(Mainnet.CRVUSD_ERC20, address(vault));
        RedemptionHandlerMock handler = new RedemptionHandlerMock(address(stablecoin), Mainnet.CRVUSD_ERC20);
        address[] memory onlyPair = new address[](1);
        onlyPair[0] = address(pair);

        vm.mockCall(address(registry), abi.encodeWithSelector(IResupplyRegistry.redemptionHandler.selector), abi.encode(address(handler)));
        vm.mockCall(address(registry), abi.encodeWithSelector(IResupplyRegistry.getAllPairAddresses.selector), abi.encode(onlyPair));
        _mockCrvUsdFunding(notionalWad, 0);
        vm.mockCall(redemptionOperator.sCrvUsd(), abi.encodeCall(IERC4626.previewDeposit, (notionalWad)), abi.encode(notionalWad));
        vm.mockCall(redemptionOperator.reusdScrvPool(), abi.encodeCall(ICurveExchange.get_dy, (redemptionOperator.scrvIndex(), redemptionOperator.reusdIndexScrv(), notionalWad)), abi.encode(redeemAmount));
        deal(redemptionOperator.usdc(), redemptionOperator.morpho(), 0);

        bytes memory failure = abi.encodeWithSignature("Error(string)", "pool failure");
        vm.mockCallRevert(redemptionOperator.crvUsdFrxUsdPool(), abi.encodeCall(ICurveExchange.get_dy, (redemptionOperator.crvUsdIndexFrxPool(), redemptionOperator.frxUsdIndexFrxPool(), notionalWad)), failure);

        vm.expectRevert(failure);
        keeper.isProfitable(notionalWad);
    }

    function test_IsProfitable_UnexpectedRegistryFailureBubbles() public {
        bytes memory failure = abi.encodeWithSignature("Error(string)", "registry failure");
        vm.mockCallRevert(address(registry), abi.encodeWithSelector(IResupplyRegistry.getAllPairAddresses.selector), failure);

        vm.expectRevert(failure);
        keeper.isProfitable(10_000e18);
    }

    function test_UnsupportedPairUnderlyingReturnsZeroAndRevertsExecution() public {
        RedemptionVaultMock vault = new RedemptionVaultMock();
        RedemptionPairMock pair = new RedemptionPairMock(address(1), address(vault));
        address[] memory onlyPair = new address[](1);
        onlyPair[0] = address(pair);
        vm.mockCall(address(registry), abi.encodeWithSelector(IResupplyRegistry.getAllPairAddresses.selector), abi.encode(onlyPair));

        _assertNoQuote(_quote(10_000e18));

        vm.prank(bot);
        vm.expectRevert("incompatible pair");
        keeper.executeRedemption(address(pair), ROUTE_CRVUSD_TO_CRVUSD, 10_000e18, 1, 1, type(uint256).max);
    }

    function test_UsdcRoundTrip_PreservesDustAndRepaysExactPrincipal() public {
        _disableCrvUsdFunding();
        KeeperQuote memory quote = _quote(10_000e18);
        assertNotEq(quote.pair, address(0));
        assertEq(quote.routeId, ROUTE_USDC_TO_FRXUSD);

        (address[6] memory dustTokens, uint256[6] memory dust) = _seedOperatorDust();

        uint256 morphoUsdcBefore = IERC20(quote.loanAsset).balanceOf(redemptionOperator.morpho());
        uint256 treasuryBefore = IERC20(Mainnet.CRVUSD_ERC20).balanceOf(Protocol.TREASURY);

        vm.prank(bot);
        keeper.executeRedemption(quote.pair, quote.routeId, quote.loanAmount, quote.redeemAmount * 9980 / 10_000, quote.expectedProfit / 2, type(uint256).max);

        assertEq(IERC20(quote.loanAsset).balanceOf(redemptionOperator.morpho()), morphoUsdcBefore);
        assertGe(IERC20(Mainnet.CRVUSD_ERC20).balanceOf(Protocol.TREASURY) - treasuryBefore, quote.expectedProfit / 2);
        _assertOperatorDust(dustTokens, dust);
    }

    function test_UsdcRoute_DustCannotSatisfyMinProfit() public {
        _disableCrvUsdFunding();
        KeeperQuote memory quote = _quote(10_000e18);
        assertNotEq(quote.pair, address(0));
        assertEq(quote.routeId, ROUTE_USDC_TO_FRXUSD);

        uint256 crvDust = 1000e18;
        deal(redemptionOperator.crvUsd(), address(redemptionOperator), crvDust);

        vm.prank(bot);
        vm.expectRevert("not profitable");
        keeper.executeRedemption(quote.pair, quote.routeId, quote.loanAmount, quote.redeemAmount * 9980 / 10_000, quote.expectedProfit + crvDust / 2, type(uint256).max);
    }

    function test_ExecuteRedemption_DoesNotReselectAfterQuoteMoves() public {
        uint256 notionalWad = 10_000e18;
        _disableCrvUsdFunding();
        KeeperQuote memory quote = _quote(notionalWad);
        assertEq(quote.routeId, ROUTE_USDC_TO_FRXUSD);

        _mockCrvUsdFunding(notionalWad, 0);
        bytes memory failure = abi.encodeWithSignature("Error(string)", "selected route unavailable");
        vm.mockCallRevert(redemptionOperator.morpho(), abi.encodeWithSelector(IMorpho.flashLoan.selector), failure);

        vm.prank(bot);
        vm.expectRevert(failure);
        keeper.executeRedemption(quote.pair, quote.routeId, quote.loanAmount, quote.redeemAmount * 9980 / 10_000, quote.expectedProfit / 2, type(uint256).max);
    }

    function test_ForkQuoteProductionGrid() public view {
        bool foundOpportunity;
        for (uint256 notional = 5000; notional <= 80_000; notional += 5000) {
            KeeperQuote memory quote = _quote(notional * 1e18);
            foundOpportunity = foundOpportunity || quote.pair != address(0);
        }
        assertTrue(foundOpportunity);
    }

    function test_ExecuteRedemption_MinSwapTooHighReverts() public {
        address pairAddress = _findPair(Mainnet.CRVUSD_ERC20);
        require(pairAddress != address(0), "pair not found");
        IResupplyPair pair = IResupplyPair(pairAddress);
        _seedPair(pair);

        vm.prank(bot);
        vm.expectRevert();
        keeper.executeRedemption(pairAddress, ROUTE_CRVUSD_TO_CRVUSD, 1000e18, type(uint256).max, 1, type(uint256).max);
    }

    function test_ExecuteRedemption_RejectsUsdcForCrvUsdPair() public {
        address pairAddress = _findPair(Mainnet.CRVUSD_ERC20);
        require(pairAddress != address(0), "pair not found");

        vm.prank(bot);
        vm.expectRevert("incompatible pair");
        keeper.executeRedemption(pairAddress, ROUTE_USDC_TO_FRXUSD, 1000e6, 1, 1, type(uint256).max);
    }

    function test_ExecuteRedemption_RequiresMinProfit() public {
        address pairAddress = _findPair(Mainnet.CRVUSD_ERC20);
        require(pairAddress != address(0), "pair not found");

        vm.prank(bot);
        vm.expectRevert("invalid min profit");
        keeper.executeRedemption(pairAddress, ROUTE_CRVUSD_TO_CRVUSD, 1000e18, 1, 0, type(uint256).max);
    }

    function test_ExecuteRedemption_RequiresLoanAmount() public {
        vm.prank(bot);
        vm.expectRevert("invalid loan amount");
        keeper.executeRedemption(address(0), ROUTE_CRVUSD_TO_CRVUSD, 0, 1, 1, type(uint256).max);
    }

    function test_ExecuteRedemption_RejectsUnsupportedRoute() public {
        vm.prank(bot);
        vm.expectRevert("unsupported route");
        keeper.executeRedemption(address(1), 4, 1, 1, 1, type(uint256).max);
    }

    function test_CallbacksRequireActiveExecution() public {
        address crvLender = redemptionOperator.crvUsdFlashLender();
        address crv = redemptionOperator.crvUsd();
        address morpho = redemptionOperator.morpho();

        vm.prank(crvLender);
        vm.expectRevert("inactive callback");
        redemptionOperator.onFlashLoan(address(redemptionOperator), crv, 1, 0, bytes(""));

        vm.prank(morpho);
        vm.expectRevert("inactive callback");
        redemptionOperator.onMorphoFlashLoan(1, bytes(""));
    }

    function test_CallbacksAuthenticateActiveLoanData() public {
        address operator = address(redemptionOperator);
        address morpho = redemptionOperator.morpho();
        address lender = redemptionOperator.crvUsdFlashLender();
        address crv = redemptionOperator.crvUsd();
        vm.store(operator, REENTRANCY_GUARD_SLOT, bytes32(uint256(2)));

        CallbackDataFixture memory morphoData = CallbackDataFixture({ caller: bot, pair: address(1), routeId: ROUTE_USDC_TO_FRXUSD, loanAmount: 2, minReusdFromSwap: 1, minProfit: 1, maxFeePct: type(uint256).max });
        bytes memory encodedMorphoData = abi.encode(morphoData);
        vm.store(operator, ACTIVE_CALLBACK_HASH_SLOT, keccak256(encodedMorphoData));

        vm.prank(address(1));
        vm.expectRevert("invalid callback caller");
        redemptionOperator.onMorphoFlashLoan(2, encodedMorphoData);

        vm.prank(morpho);
        vm.expectRevert("invalid callback amount");
        redemptionOperator.onMorphoFlashLoan(1, encodedMorphoData);

        CallbackDataFixture memory wrongRouteData = morphoData;
        wrongRouteData.routeId = ROUTE_CRVUSD_TO_FRXUSD;
        vm.prank(morpho);
        vm.expectRevert("invalid callback route");
        redemptionOperator.onMorphoFlashLoan(2, abi.encode(wrongRouteData));
        morphoData.routeId = ROUTE_USDC_TO_FRXUSD;

        CallbackDataFixture memory changedMorphoPayload = morphoData;
        changedMorphoPayload.caller = address(2);
        vm.prank(morpho);
        vm.expectRevert("invalid callback data");
        redemptionOperator.onMorphoFlashLoan(2, abi.encode(changedMorphoPayload));

        CallbackDataFixture memory crvData = CallbackDataFixture({ caller: bot, pair: address(1), routeId: ROUTE_CRVUSD_TO_CRVUSD, loanAmount: 2, minReusdFromSwap: 1, minProfit: 1, maxFeePct: type(uint256).max });
        bytes memory encodedCrvData = abi.encode(crvData);
        vm.store(operator, ACTIVE_CALLBACK_HASH_SLOT, keccak256(encodedCrvData));

        vm.prank(address(1));
        vm.expectRevert("invalid callback caller");
        redemptionOperator.onFlashLoan(operator, crv, 2, 0, encodedCrvData);

        vm.prank(lender);
        vm.expectRevert("invalid initiator");
        redemptionOperator.onFlashLoan(address(1), crv, 2, 0, encodedCrvData);

        vm.prank(lender);
        vm.expectRevert("invalid token");
        redemptionOperator.onFlashLoan(operator, address(1), 2, 0, encodedCrvData);

        vm.prank(lender);
        vm.expectRevert("invalid callback amount");
        redemptionOperator.onFlashLoan(operator, crv, 1, 0, encodedCrvData);

        CallbackDataFixture memory wrongCrvRouteData = crvData;
        wrongCrvRouteData.routeId = ROUTE_USDC_TO_FRXUSD;
        vm.prank(lender);
        vm.expectRevert("invalid callback route");
        redemptionOperator.onFlashLoan(operator, crv, 2, 0, abi.encode(wrongCrvRouteData));
        crvData.routeId = ROUTE_CRVUSD_TO_CRVUSD;

        CallbackDataFixture memory changedCrvPayload = crvData;
        changedCrvPayload.maxFeePct = 1;
        vm.prank(lender);
        vm.expectRevert("invalid callback data");
        redemptionOperator.onFlashLoan(operator, crv, 2, 0, abi.encode(changedCrvPayload));

        vm.store(operator, REENTRANCY_GUARD_SLOT, bytes32(uint256(1)));
        vm.store(operator, ACTIVE_CALLBACK_HASH_SLOT, bytes32(0));
    }

    function test_AllApprovals_CanRevokeAndReset() public {
        _assertAllAllowances(type(uint256).max);

        vm.prank(Protocol.DEPLOYER);
        redemptionOperator.revokeAllApprovals();
        _assertAllAllowances(0);

        vm.prank(Protocol.DEPLOYER);
        redemptionOperator.setApprovals();
        _assertAllAllowances(type(uint256).max);
    }

    function test_AllApprovals_Restricted() public {
        vm.startPrank(address(1));
        vm.expectRevert("!authorized");
        redemptionOperator.revokeAllApprovals();
        vm.expectRevert("!authorized");
        redemptionOperator.setApprovals();
        vm.expectRevert("!authorized");
        redemptionOperator.approveRH();
        vm.stopPrank();
    }

    function test_ManagerCanSetApprovedCaller() public {
        address caller = address(0xBEEF);
        assertEq(redemptionOperator.manager(), Protocol.DEPLOYER);
        assertFalse(redemptionOperator.approvedCallers(caller));

        vm.prank(Protocol.DEPLOYER);
        redemptionOperator.setApprovedCaller(caller, true);
        assertTrue(redemptionOperator.approvedCallers(caller));
    }

    function test_SetApprovedCaller_NotOwnerOrManager() public {
        vm.prank(address(1));
        vm.expectRevert("!authorized");
        redemptionOperator.setApprovedCaller(address(0xBEEF), true);
    }

    function test_UpgradeOperator_CanUpgradeRedemptionOperator() public {
        UpgradeOperator upgradeOperator = new UpgradeOperator(Protocol.CORE, Protocol.DEPLOYER);
        address newImplementation = address(new RedemptionOperator());

        vm.prank(address(core));
        core.setOperatorPermissions(address(upgradeOperator), address(redemptionOperator), IUpgradeableOperator.upgradeToAndCall.selector, true, IAuthHook(address(0)));

        address implBefore = Upgrades.getImplementationAddress(address(redemptionOperator));
        vm.prank(Protocol.DEPLOYER);
        upgradeOperator.upgradeToAndCall(address(redemptionOperator), newImplementation, "");
        address implAfter = Upgrades.getImplementationAddress(address(redemptionOperator));

        assertNotEq(implAfter, implBefore);
        assertEq(implAfter, newImplementation);
    }

    function test_UpgradeOperator_RequiresCorePermission() public {
        UpgradeOperator upgradeOperator = new UpgradeOperator(Protocol.CORE, Protocol.DEPLOYER);
        address newImplementation = address(new RedemptionOperator());

        vm.prank(Protocol.DEPLOYER);
        vm.expectRevert("!authorized");
        upgradeOperator.upgradeToAndCall(address(redemptionOperator), newImplementation, "");
    }

    function test_UpgradeOperator_NotOwner() public {
        UpgradeOperator upgradeOperator = new UpgradeOperator(Protocol.CORE, Protocol.DEPLOYER);
        address newImplementation = address(new RedemptionOperator());

        vm.prank(address(1));
        vm.expectRevert("!authorized");
        upgradeOperator.upgradeToAndCall(address(redemptionOperator), newImplementation, "");
    }

    function test_StorageLayoutIsCompatibleWithProductionImplementation() public {
        // OpenZeppelin validates every build-info shard, so CI runs this with an isolated output directory.
        if (!vm.envOr("RUN_STORAGE_LAYOUT_VALIDATION", false)) vm.skip(true);

        Options memory options;
        options.referenceContract = STORAGE_REFERENCE;
        Upgrades.validateUpgrade("RedemptionOperator.sol:RedemptionOperator", options);
    }

    function test_ForkUpgradeProductionProxy_PreservesStateAndInstallsApprovals() public {
        RedemptionOperator production = RedemptionOperator(Protocol.OPERATOR_REDEMPTION_PROXY);
        address managerBefore = production.manager();
        address handler = registry.redemptionHandler();
        bytes32 reentrancyStateBefore = vm.load(address(production), REENTRANCY_GUARD_SLOT);
        address[3] memory callers = [Protocol.DEPLOYER, 0x1ba323F8a6544b81Dc1F068b1400A6ebe7Ea0f52, 0x051C42Ee7A529410a10E5Ec11B9E9b8bA7cbb795];
        for (uint256 i = 0; i < callers.length; i++) {
            assertTrue(production.approvedCallers(callers[i]));
        }

        address implementation = address(new RedemptionOperator());
        vm.prank(address(core));
        IUpgradeableOperator(address(production)).upgradeToAndCall(implementation, abi.encodeCall(RedemptionOperator.setApprovals, ()));

        assertEq(Upgrades.getImplementationAddress(address(production)), implementation);
        assertEq(production.owner(), Protocol.CORE);
        assertEq(production.manager(), managerBefore);
        assertEq(vm.load(address(production), REENTRANCY_GUARD_SLOT), reentrancyStateBefore);
        for (uint256 i = 0; i < callers.length; i++) {
            assertTrue(production.approvedCallers(callers[i]));
        }
        assertEq(IERC20(production.reusd()).allowance(address(production), handler), type(uint256).max);
        assertEq(IERC20(production.usdc()).allowance(address(production), production.frxUsdCustodian()), type(uint256).max);
        assertEq(IERC20(production.frxUsd()).allowance(address(production), production.frxUsdCustodian()), type(uint256).max);
        assertEq(IERC20(production.usdc()).allowance(address(production), production.morpho()), type(uint256).max);

        vm.startPrank(address(1));
        vm.expectRevert("!authorized");
        production.setApprovals();
        vm.expectRevert("!authorized");
        production.revokeAllApprovals();
        vm.stopPrank();

        address morpho = production.morpho();
        vm.prank(morpho);
        vm.expectRevert("inactive callback");
        production.onMorphoFlashLoan(1, bytes(""));
    }

    function _quote(uint256 notionalWad) internal view returns (KeeperQuote memory quote) {
        (quote.pair, quote.expectedProfit, quote.redeemAmount, quote.routeId, quote.loanAsset, quote.loanAmount) = keeper.isProfitable(notionalWad);
    }

    function _assertNoQuote(KeeperQuote memory quote) internal pure {
        assertEq(quote.pair, address(0));
        assertEq(quote.expectedProfit, 0);
        assertEq(quote.redeemAmount, 0);
        assertEq(quote.routeId, ROUTE_NONE);
        assertEq(quote.loanAsset, address(0));
        assertEq(quote.loanAmount, 0);
    }

    function _disableCrvUsdFunding() internal {
        vm.mockCall(redemptionOperator.crvUsdFlashLender(), abi.encodeCall(IERC3156FlashLender.maxFlashLoan, (redemptionOperator.crvUsd())), abi.encode(0));
    }

    function _mockCrvUsdFunding(uint256 loanAmount, uint256 fee) internal {
        vm.mockCall(redemptionOperator.crvUsdFlashLender(), abi.encodeCall(IERC3156FlashLender.maxFlashLoan, (redemptionOperator.crvUsd())), abi.encode(type(uint256).max));
        vm.mockCall(redemptionOperator.crvUsdFlashLender(), abi.encodeCall(IERC3156FlashLender.flashFee, (redemptionOperator.crvUsd(), loanAmount)), abi.encode(fee));
    }

    function _mockOnlyCrvUsdToCrvUsdFunding(uint256 loanAmount, uint256 redeemAmount) internal {
        _mockCrvUsdFunding(loanAmount, 0);
        vm.mockCall(redemptionOperator.sCrvUsd(), abi.encodeCall(IERC4626.previewDeposit, (loanAmount)), abi.encode(loanAmount));
        vm.mockCall(redemptionOperator.reusdScrvPool(), abi.encodeCall(ICurveExchange.get_dy, (redemptionOperator.scrvIndex(), redemptionOperator.reusdIndexScrv(), loanAmount)), abi.encode(redeemAmount));
        vm.mockCall(redemptionOperator.crvUsdFrxUsdPool(), abi.encodeCall(ICurveExchange.get_dy, (redemptionOperator.crvUsdIndexFrxPool(), redemptionOperator.frxUsdIndexFrxPool(), loanAmount)), abi.encode(0));
        deal(redemptionOperator.usdc(), redemptionOperator.morpho(), 0);
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
        _ensureDebt(pair);
    }

    function _findCrvReplay(address pair, address reusdPool, uint256 reusdToSell) internal returns (KeeperQuote memory quote) {
        require(pair != address(0), "pair not found");
        address[] memory onlyPair = new address[](1);
        onlyPair[0] = pair;
        vm.mockCall(address(registry), abi.encodeWithSelector(registry.getAllPairAddresses.selector), abi.encode(onlyPair));
        _ensureDebt(IResupplyPair(pair));

        uint256[3] memory flashAmounts = [uint256(10_000e18), 5000e18, 1000e18];
        IERC20(redemptionOperator.reusd()).forceApprove(reusdPool, type(uint256).max);

        for (uint256 i = 0; i < 3; i++) {
            deal(redemptionOperator.reusd(), address(this), reusdToSell);
            ICurveExchange(reusdPool).exchange(0, 1, reusdToSell, 0, address(this));

            for (uint256 j = 0; j < flashAmounts.length; j++) {
                quote = _quote(flashAmounts[j]);
                if (quote.pair == pair && quote.routeId == ROUTE_CRVUSD_TO_FRXUSD && quote.expectedProfit != 0) {
                    return quote;
                }
            }
            reusdToSell *= 2;
        }
    }

    function _seedOperatorDust() internal returns (address[6] memory tokens, uint256[6] memory amounts) {
        tokens = [redemptionOperator.usdc(), redemptionOperator.frxUsd(), redemptionOperator.crvUsd(), redemptionOperator.sFrxUsd(), redemptionOperator.sCrvUsd(), redemptionOperator.reusd()];
        amounts = [uint256(123_456), uint256(2e18), uint256(3e18), uint256(4e18), uint256(5e18), uint256(6e18)];

        for (uint256 i = 0; i < tokens.length; i++) {
            deal(tokens[i], address(redemptionOperator), amounts[i]);
        }
    }

    function _assertOperatorDust(address[6] memory tokens, uint256[6] memory amounts) internal view {
        for (uint256 i = 0; i < tokens.length; i++) {
            assertEq(IERC20(tokens[i]).balanceOf(address(redemptionOperator)), amounts[i]);
        }
    }

    function _assertAllAllowances(uint256 expected) internal view {
        assertEq(IERC20(redemptionOperator.crvUsd()).allowance(address(redemptionOperator), redemptionOperator.sCrvUsd()), expected);
        assertEq(IERC20(redemptionOperator.sCrvUsd()).allowance(address(redemptionOperator), redemptionOperator.reusdScrvPool()), expected);
        assertEq(IERC20(redemptionOperator.reusd()).allowance(address(redemptionOperator), redemptionOperator.reusdScrvPool()), expected);
        assertEq(IERC20(redemptionOperator.frxUsd()).allowance(address(redemptionOperator), redemptionOperator.frxusdSfrxusdPool()), expected);
        assertEq(IERC20(redemptionOperator.sFrxUsd()).allowance(address(redemptionOperator), redemptionOperator.reusdSfrxPool()), expected);
        assertEq(IERC20(redemptionOperator.reusd()).allowance(address(redemptionOperator), redemptionOperator.reusdSfrxPool()), expected);
        assertEq(IERC20(redemptionOperator.sFrxUsd()).allowance(address(redemptionOperator), redemptionOperator.frxusdSfrxusdPool()), expected);
        assertEq(IERC20(redemptionOperator.crvUsd()).allowance(address(redemptionOperator), redemptionOperator.crvUsdFrxUsdPool()), expected);
        assertEq(IERC20(redemptionOperator.frxUsd()).allowance(address(redemptionOperator), redemptionOperator.crvUsdFrxUsdPool()), expected);
        assertEq(IERC20(redemptionOperator.usdc()).allowance(address(redemptionOperator), redemptionOperator.frxUsdCustodian()), expected);
        assertEq(IERC20(redemptionOperator.frxUsd()).allowance(address(redemptionOperator), redemptionOperator.frxUsdCustodian()), expected);
        assertEq(IERC20(redemptionOperator.usdc()).allowance(address(redemptionOperator), redemptionOperator.morpho()), expected);
        assertEq(IERC20(redemptionOperator.reusd()).allowance(address(redemptionOperator), address(redemptionHandler)), expected);
    }
}
