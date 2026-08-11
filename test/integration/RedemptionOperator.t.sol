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
import { IERC4626 } from "src/interfaces/IERC4626.sol";
import { ICurveExchange } from "src/interfaces/curve/ICurveExchange.sol";
import { IAuthHook } from "src/interfaces/IAuthHook.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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

    function previewRedeem(address, uint256 amount)
        external
        pure
        returns (uint256 underlyingOut, uint256 collateralShares, uint256 fee)
    {
        return (amount * 110 / 100, amount, 1e16);
    }

    function redeemFromPair(address, uint256 amount, uint256, address receiver, bool)
        external
        returns (uint256 underlyingOut)
    {
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
    bytes32 internal constant REENTRANCY_GUARD_SLOT =
        0x9b779b17422d0df92223018b32b4d1fa46e071723d6817e2486d003becc55f00;
    string internal constant STORAGE_REFERENCE =
        "RedemptionOperator.t.sol:RedemptionOperatorV1Storage";

    struct CallbackDataFixture {
        address caller;
        address pair;
        address loanAsset;
        uint256 flashAmount;
        uint256 minReusdFromSwap;
        uint256 minProfit;
        uint256 maxFeePct;
    }

    RedemptionOperator public redemptionOperator;
    address public bot = address(0xB0B);

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
        address proxy = Upgrades.deployUUPSProxy(
            "RedemptionOperator.sol:RedemptionOperator",
            initializerData,
            options
        );
        redemptionOperator = RedemptionOperator(proxy);

        vm.prank(address(core));
        registry.setAddress("REDEMPTION_OPERATOR", proxy);
    }

    function test_IsProfitable_Zero() public {
        (address pair, uint256 profit, uint256 redeemAmount) =
            redemptionOperator.isProfitable(0, redemptionOperator.crvUsd());
        assertEq(pair, address(0));
        assertEq(profit, 0);
        assertEq(redeemAmount, 0);
    }

    function test_IsProfitable_UnsupportedAsset() public {
        (address pair, uint256 profit, uint256 redeemAmount) =
            redemptionOperator.isProfitable(10_000e18, address(1));
        assertEq(pair, address(0));
        assertEq(profit, 0);
        assertEq(redeemAmount, 0);
    }

    function test_CrvUsdToCrvUsd_RoundTrip() public {
        RedemptionVaultMock vault = new RedemptionVaultMock();
        RedemptionPairMock pair = new RedemptionPairMock(Mainnet.CRVUSD_ERC20, address(vault));
        RedemptionHandlerMock handler =
            new RedemptionHandlerMock(address(stablecoin), Mainnet.CRVUSD_ERC20);

        vm.mockCall(
            address(registry),
            abi.encodeWithSelector(IResupplyRegistry.redemptionHandler.selector),
            abi.encode(address(handler))
        );
        address[] memory onlyPair = new address[](1);
        onlyPair[0] = address(pair);
        vm.mockCall(
            address(registry),
            abi.encodeWithSelector(IResupplyRegistry.getAllPairAddresses.selector),
            abi.encode(onlyPair)
        );
        _deployRedemptionOperator();
        deal(Mainnet.CRVUSD_ERC20, address(handler), 1_000_000e18);
        (address[6] memory dustTokens, uint256[6] memory dust) = _seedOperatorDust();

        address loanAsset = redemptionOperator.crvUsd();
        uint256 flashAmount = 10_000e18;
        (address bestPair, uint256 profit, uint256 redeemAmount) =
            redemptionOperator.isProfitable(flashAmount, loanAsset);
        assertEq(bestPair, address(pair));
        assertGt(profit, 0);

        uint256 treasuryBefore = IERC20(Mainnet.CRVUSD_ERC20).balanceOf(Protocol.TREASURY);
        vm.prank(bot);
        redemptionOperator.executeRedemption(
            bestPair,
            loanAsset,
            flashAmount,
            redeemAmount * 9_980 / 10_000,
            profit / 2,
            type(uint256).max
        );
        uint256 treasuryAfter = IERC20(Mainnet.CRVUSD_ERC20).balanceOf(Protocol.TREASURY);
        assertGt(treasuryAfter - treasuryBefore, 0, "profit not recorded");
        _assertOperatorDust(dustTokens, dust);
    }

    function test_CrvUsdToFrxUsd_HistoricalReplay() public {
        address loanAsset = redemptionOperator.crvUsd();
        address expectedPair = _findPair(Mainnet.FRXUSD_ERC20);
        (uint256 flashAmount, uint256 profit, uint256 redeemAmount) =
            _findCrvReplay(expectedPair, redemptionOperator.reusdSfrxPool(), 500_000e18);
        assertGt(flashAmount, 0);
        (address[6] memory dustTokens, uint256[6] memory dust) = _seedOperatorDust();

        uint256 treasuryBefore = IERC20(Mainnet.CRVUSD_ERC20).balanceOf(Protocol.TREASURY);
        vm.prank(bot);
        redemptionOperator.executeRedemption(
            expectedPair,
            loanAsset,
            flashAmount,
            redeemAmount * 9_980 / 10_000,
            profit / 2,
            type(uint256).max
        );
        assertGe(
            IERC20(Mainnet.CRVUSD_ERC20).balanceOf(Protocol.TREASURY) - treasuryBefore,
            profit / 2
        );
        _assertOperatorDust(dustTokens, dust);
    }

    function test_IsProfitable_UsdcOnlyReturnsFrxUsdPair() public view {
        (address pair, uint256 profit, uint256 redeemAmount) =
            redemptionOperator.isProfitable(10_000e6, redemptionOperator.usdc());
        assertNotEq(pair, address(0));
        assertGt(profit, 0);
        assertGt(redeemAmount, 0);
        assertEq(IResupplyPair(pair).underlying(), Mainnet.FRXUSD_ERC20);

        (uint256 underlyingOut, uint256 collateralShares, uint256 fee) =
            IRedemptionHandler(address(redemptionHandler)).previewRedeem(pair, redeemAmount);
        assertGt(underlyingOut, 0);
        assertGt(collateralShares, 0);
        assertGt(fee, 0);
        assertLe(collateralShares, IERC4626(IResupplyPair(pair).collateral()).maxRedeem(pair));
    }

    function test_IsProfitable_UsdcRequiresMorphoLiquidity() public {
        uint256 flashAmount = 10_000e6;
        deal(redemptionOperator.usdc(), redemptionOperator.morpho(), flashAmount - 1);

        (address pair, uint256 profit, uint256 redeemAmount) =
            redemptionOperator.isProfitable(flashAmount, redemptionOperator.usdc());
        assertEq(pair, address(0));
        assertEq(profit, 0);
        assertEq(redeemAmount, 0);
    }

    function test_IsProfitable_UsdcRespectsCustodianCap() public {
        uint256 flashAmount = 10_000e6;
        vm.mockCall(
            redemptionOperator.frxUsdCustodian(),
            abi.encodeCall(IERC4626.maxDeposit, (address(redemptionOperator))),
            abi.encode(flashAmount - 1)
        );

        (address pair, uint256 profit, uint256 redeemAmount) =
            redemptionOperator.isProfitable(flashAmount, redemptionOperator.usdc());
        assertEq(pair, address(0));
        assertEq(profit, 0);
        assertEq(redeemAmount, 0);
    }

    function test_IsProfitable_UsdcUsesCustodianPreviewRounding() public {
        uint256 flashAmount = 10_000e6;
        uint256 frxMinted = 9_999e18 + 7;
        uint256 sfrxOut = frxMinted - 13;
        uint256 reusdOut = sfrxOut - 17;
        uint256 underlyingOut = reusdOut * 110 / 100;
        uint256 frxForUsdc = 10_002e18 + 19;
        uint256 expectedProfit = 995e18;

        RedemptionVaultMock vault = new RedemptionVaultMock();
        RedemptionPairMock pair = new RedemptionPairMock(Mainnet.FRXUSD_ERC20, address(vault));
        RedemptionHandlerMock handler =
            new RedemptionHandlerMock(address(stablecoin), Mainnet.FRXUSD_ERC20);
        address[] memory onlyPair = new address[](1);
        onlyPair[0] = address(pair);

        vm.mockCall(
            address(registry),
            abi.encodeWithSelector(IResupplyRegistry.redemptionHandler.selector),
            abi.encode(address(handler))
        );
        vm.mockCall(
            address(registry),
            abi.encodeWithSelector(IResupplyRegistry.getAllPairAddresses.selector),
            abi.encode(onlyPair)
        );
        vm.mockCall(
            redemptionOperator.frxUsdCustodian(),
            abi.encodeCall(IERC4626.maxDeposit, (address(redemptionOperator))),
            abi.encode(type(uint256).max)
        );
        vm.mockCall(
            redemptionOperator.frxUsdCustodian(),
            abi.encodeCall(IERC4626.previewDeposit, (flashAmount)),
            abi.encode(frxMinted)
        );
        vm.mockCall(
            redemptionOperator.frxUsdCustodian(),
            abi.encodeCall(IERC4626.previewWithdraw, (flashAmount)),
            abi.encode(frxForUsdc)
        );
        vm.mockCall(
            redemptionOperator.frxusdSfrxusdPool(),
            abi.encodeCall(
                ICurveExchange.get_dy,
                (
                    redemptionOperator.frxusdIndexFraxPool(),
                    redemptionOperator.sfrxusdIndexFraxPool(),
                    frxMinted
                )
            ),
            abi.encode(sfrxOut)
        );
        vm.mockCall(
            redemptionOperator.reusdSfrxPool(),
            abi.encodeCall(
                ICurveExchange.get_dy,
                (
                    redemptionOperator.sfrxIndex(),
                    redemptionOperator.reusdIndexSfrx(),
                    sfrxOut
                )
            ),
            abi.encode(reusdOut)
        );
        vm.mockCall(
            redemptionOperator.crvUsdFrxUsdPool(),
            abi.encodeCall(
                ICurveExchange.get_dy,
                (
                    redemptionOperator.frxUsdIndexFrxPool(),
                    redemptionOperator.crvUsdIndexFrxPool(),
                    underlyingOut - frxForUsdc
                )
            ),
            abi.encode(expectedProfit)
        );

        (address bestPair, uint256 profit, uint256 redeemAmount) =
            redemptionOperator.isProfitable(flashAmount, redemptionOperator.usdc());
        assertEq(bestPair, address(pair));
        assertEq(profit, expectedProfit);
        assertEq(redeemAmount, reusdOut);
    }

    function test_UnsupportedPairUnderlyingReturnsZeroAndRevertsExecution() public {
        RedemptionVaultMock vault = new RedemptionVaultMock();
        RedemptionPairMock pair = new RedemptionPairMock(address(1), address(vault));
        address loanAsset = redemptionOperator.crvUsd();
        address[] memory onlyPair = new address[](1);
        onlyPair[0] = address(pair);
        vm.mockCall(
            address(registry),
            abi.encodeWithSelector(IResupplyRegistry.getAllPairAddresses.selector),
            abi.encode(onlyPair)
        );

        (address bestPair, uint256 profit, uint256 redeemAmount) =
            redemptionOperator.isProfitable(10_000e18, loanAsset);
        assertEq(bestPair, address(0));
        assertEq(profit, 0);
        assertEq(redeemAmount, 0);

        vm.prank(bot);
        vm.expectRevert("unsupported route");
        redemptionOperator.executeRedemption(
            address(pair),
            loanAsset,
            10_000e18,
            1,
            1,
            type(uint256).max
        );
    }

    function test_UsdcRoundTrip_PreservesDustAndRepaysExactPrincipal() public {
        address loanAsset = redemptionOperator.usdc();
        uint256 flashAmount = 10_000e6;
        (address pair, uint256 expectedProfit, uint256 redeemAmount) =
            redemptionOperator.isProfitable(flashAmount, loanAsset);
        assertNotEq(pair, address(0));

        (address[6] memory dustTokens, uint256[6] memory dust) = _seedOperatorDust();

        uint256 morphoUsdcBefore = IERC20(loanAsset).balanceOf(redemptionOperator.morpho());
        uint256 treasuryBefore = IERC20(Mainnet.CRVUSD_ERC20).balanceOf(Protocol.TREASURY);

        vm.prank(bot);
        redemptionOperator.executeRedemption(
            pair,
            loanAsset,
            flashAmount,
            redeemAmount * 9_980 / 10_000,
            expectedProfit / 2,
            type(uint256).max
        );

        assertEq(IERC20(loanAsset).balanceOf(redemptionOperator.morpho()), morphoUsdcBefore);
        assertGe(
            IERC20(Mainnet.CRVUSD_ERC20).balanceOf(Protocol.TREASURY) - treasuryBefore,
            expectedProfit / 2
        );
        _assertOperatorDust(dustTokens, dust);
    }

    function test_UsdcRoute_DustCannotSatisfyMinProfit() public {
        address loanAsset = redemptionOperator.usdc();
        uint256 flashAmount = 10_000e6;
        (address pair, uint256 expectedProfit, uint256 redeemAmount) =
            redemptionOperator.isProfitable(flashAmount, loanAsset);
        assertNotEq(pair, address(0));

        uint256 crvDust = 1_000e18;
        deal(redemptionOperator.crvUsd(), address(redemptionOperator), crvDust);

        vm.prank(bot);
        vm.expectRevert("not profitable");
        redemptionOperator.executeRedemption(
            pair,
            loanAsset,
            flashAmount,
            redeemAmount * 9_980 / 10_000,
            expectedProfit + crvDust / 2,
            type(uint256).max
        );
    }

    function test_ForkQuoteProductionGrid() public view {
        bool foundUsdcRoute;
        for (uint256 notional = 5_000; notional <= 80_000; notional += 5_000) {
            redemptionOperator.isProfitable(notional * 1e18, redemptionOperator.crvUsd());
            (address usdcPair,,) =
                redemptionOperator.isProfitable(notional * 1e6, redemptionOperator.usdc());
            foundUsdcRoute = foundUsdcRoute || usdcPair != address(0);
        }
        assertTrue(foundUsdcRoute);
    }

    function test_ExecuteRedemption_MinSwapTooHighReverts() public {
        address pairAddress = _findPair(Mainnet.CRVUSD_ERC20);
        require(pairAddress != address(0), "pair not found");
        IResupplyPair pair = IResupplyPair(pairAddress);
        _seedPair(pair);
        address loanAsset = redemptionOperator.crvUsd();

        vm.prank(bot);
        vm.expectRevert();
        redemptionOperator.executeRedemption(
            pairAddress,
            loanAsset,
            1_000e18,
            type(uint256).max,
            1,
            type(uint256).max
        );
    }

    function test_ExecuteRedemption_RejectsUsdcForCrvUsdPair() public {
        address pairAddress = _findPair(Mainnet.CRVUSD_ERC20);
        require(pairAddress != address(0), "pair not found");
        address loanAsset = redemptionOperator.usdc();

        vm.prank(bot);
        vm.expectRevert("unsupported route");
        redemptionOperator.executeRedemption(
            pairAddress,
            loanAsset,
            1_000e6,
            1,
            1,
            type(uint256).max
        );
    }

    function test_ExecuteRedemption_RequiresMinProfit() public {
        address pairAddress = _findPair(Mainnet.CRVUSD_ERC20);
        require(pairAddress != address(0), "pair not found");
        address loanAsset = redemptionOperator.crvUsd();

        vm.prank(bot);
        vm.expectRevert("invalid min profit");
        redemptionOperator.executeRedemption(
            pairAddress,
            loanAsset,
            1_000e18,
            1,
            0,
            type(uint256).max
        );
    }

    function test_ExecuteRedemption_RequiresFlashAmount() public {
        address loanAsset = redemptionOperator.crvUsd();
        vm.prank(bot);
        vm.expectRevert("invalid flash amount");
        redemptionOperator.executeRedemption(
            address(0),
            loanAsset,
            0,
            1,
            1,
            type(uint256).max
        );
    }

    function test_CallbacksRequireActiveExecution() public {
        address crvLender = redemptionOperator.crvUsdFlashLender();
        address crv = redemptionOperator.crvUsd();
        address morpho = redemptionOperator.morpho();

        vm.prank(crvLender);
        vm.expectRevert("inactive callback");
        redemptionOperator.onFlashLoan(
            address(redemptionOperator),
            crv,
            1,
            0,
            bytes("")
        );

        vm.prank(morpho);
        vm.expectRevert("inactive callback");
        redemptionOperator.onMorphoFlashLoan(1, bytes(""));
    }

    function test_CallbacksAuthenticateActiveLoanData() public {
        address operator = address(redemptionOperator);
        address morpho = redemptionOperator.morpho();
        address lender = redemptionOperator.crvUsdFlashLender();
        address usdc = redemptionOperator.usdc();
        address crv = redemptionOperator.crvUsd();
        vm.store(operator, REENTRANCY_GUARD_SLOT, bytes32(uint256(2)));

        CallbackDataFixture memory morphoData = CallbackDataFixture({
            caller: bot,
            pair: address(1),
            loanAsset: usdc,
            flashAmount: 2,
            minReusdFromSwap: 1,
            minProfit: 1,
            maxFeePct: type(uint256).max
        });

        vm.prank(address(1));
        vm.expectRevert("invalid callback caller");
        redemptionOperator.onMorphoFlashLoan(2, abi.encode(morphoData));

        vm.prank(morpho);
        vm.expectRevert("invalid callback data");
        redemptionOperator.onMorphoFlashLoan(1, abi.encode(morphoData));

        morphoData.loanAsset = crv;
        vm.prank(morpho);
        vm.expectRevert("invalid callback data");
        redemptionOperator.onMorphoFlashLoan(2, abi.encode(morphoData));

        CallbackDataFixture memory crvData = CallbackDataFixture({
            caller: bot,
            pair: address(1),
            loanAsset: crv,
            flashAmount: 2,
            minReusdFromSwap: 1,
            minProfit: 1,
            maxFeePct: type(uint256).max
        });

        vm.prank(lender);
        vm.expectRevert("invalid initiator");
        redemptionOperator.onFlashLoan(
            address(1),
            crv,
            2,
            0,
            abi.encode(crvData)
        );

        vm.prank(lender);
        vm.expectRevert("invalid token");
        redemptionOperator.onFlashLoan(
            operator,
            address(1),
            2,
            0,
            abi.encode(crvData)
        );

        vm.prank(lender);
        vm.expectRevert("invalid callback data");
        redemptionOperator.onFlashLoan(
            operator,
            crv,
            1,
            0,
            abi.encode(crvData)
        );

        vm.store(operator, REENTRANCY_GUARD_SLOT, bytes32(uint256(1)));
    }

    function test_IntegrationApprovals_CanRevokeAndReset() public {
        _assertIntegrationAllowances(type(uint256).max);

        vm.prank(Protocol.DEPLOYER);
        redemptionOperator.revokeIntegrationApprovals();
        _assertIntegrationAllowances(0);

        vm.prank(Protocol.DEPLOYER);
        redemptionOperator.setApprovals();
        _assertIntegrationAllowances(type(uint256).max);
    }

    function test_IntegrationApprovals_Restricted() public {
        vm.startPrank(address(1));
        vm.expectRevert("!authorized");
        redemptionOperator.revokeIntegrationApprovals();
        vm.expectRevert("!authorized");
        redemptionOperator.setApprovals();
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
        Options memory options;
        options.referenceContract = STORAGE_REFERENCE;
        Upgrades.validateUpgrade("RedemptionOperator.sol:RedemptionOperator", options);
    }

    function test_ForkUpgradeProductionProxy_PreservesStateAndInstallsApprovals() public {
        RedemptionOperator production = RedemptionOperator(Protocol.OPERATOR_REDEMPTION_PROXY);
        address managerBefore = production.manager();
        address handler = registry.redemptionHandler();
        bytes32 reentrancyStateBefore =
            vm.load(address(production), REENTRANCY_GUARD_SLOT);
        address[3] memory callers = [
            Protocol.DEPLOYER,
            0x1ba323F8a6544b81Dc1F068b1400A6ebe7Ea0f52,
            0x051C42Ee7A529410a10E5Ec11B9E9b8bA7cbb795
        ];
        for (uint256 i = 0; i < callers.length; i++) {
            assertTrue(production.approvedCallers(callers[i]));
        }

        address implementation = address(new RedemptionOperator());
        vm.prank(address(core));
        IUpgradeableOperator(address(production)).upgradeToAndCall(
            implementation,
            abi.encodeCall(RedemptionOperator.setApprovals, ())
        );

        assertEq(Upgrades.getImplementationAddress(address(production)), implementation);
        assertEq(production.owner(), Protocol.CORE);
        assertEq(production.manager(), managerBefore);
        assertEq(vm.load(address(production), REENTRANCY_GUARD_SLOT), reentrancyStateBefore);
        for (uint256 i = 0; i < callers.length; i++) {
            assertTrue(production.approvedCallers(callers[i]));
        }
        assertEq(
            IERC20(production.reusd()).allowance(address(production), handler),
            type(uint256).max
        );
        assertEq(
            IERC20(production.usdc()).allowance(
                address(production),
                production.frxUsdCustodian()
            ),
            type(uint256).max
        );
        assertEq(
            IERC20(production.frxUsd()).allowance(
                address(production),
                production.frxUsdCustodian()
            ),
            type(uint256).max
        );
        assertEq(
            IERC20(production.usdc()).allowance(address(production), production.morpho()),
            type(uint256).max
        );

        vm.startPrank(address(1));
        vm.expectRevert("!authorized");
        production.setApprovals();
        vm.expectRevert("!authorized");
        production.revokeIntegrationApprovals();
        vm.stopPrank();

        address morpho = production.morpho();
        vm.prank(morpho);
        vm.expectRevert("inactive callback");
        production.onMorphoFlashLoan(1, bytes(""));
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

    function _findCrvReplay(address pair, address reusdPool, uint256 reusdToSell)
        internal
        returns (uint256 flashAmount, uint256 profit, uint256 redeemAmount)
    {
        require(pair != address(0), "pair not found");
        address[] memory onlyPair = new address[](1);
        onlyPair[0] = pair;
        vm.mockCall(
            address(registry),
            abi.encodeWithSelector(registry.getAllPairAddresses.selector),
            abi.encode(onlyPair)
        );
        _ensureDebt(IResupplyPair(pair));

        uint256[3] memory flashAmounts = [uint256(10_000e18), 5_000e18, 1_000e18];
        IERC20(redemptionOperator.reusd()).forceApprove(reusdPool, type(uint256).max);

        for (uint256 i = 0; i < 3; i++) {
            deal(redemptionOperator.reusd(), address(this), reusdToSell);
            ICurveExchange(reusdPool).exchange(0, 1, reusdToSell, 0, address(this));

            for (uint256 j = 0; j < flashAmounts.length; j++) {
                (address bestPair, uint256 candidateProfit, uint256 candidateRedeem) =
                    redemptionOperator.isProfitable(flashAmounts[j], redemptionOperator.crvUsd());
                if (bestPair == pair && candidateProfit != 0) {
                    return (flashAmounts[j], candidateProfit, candidateRedeem);
                }
            }
            reusdToSell *= 2;
        }
    }

    function _seedOperatorDust()
        internal
        returns (address[6] memory tokens, uint256[6] memory amounts)
    {
        tokens = [
            redemptionOperator.usdc(),
            redemptionOperator.frxUsd(),
            redemptionOperator.crvUsd(),
            redemptionOperator.sFrxUsd(),
            redemptionOperator.sCrvUsd(),
            redemptionOperator.reusd()
        ];
        amounts = [
            uint256(123_456),
            uint256(2e18),
            uint256(3e18),
            uint256(4e18),
            uint256(5e18),
            uint256(6e18)
        ];

        for (uint256 i = 0; i < tokens.length; i++) {
            deal(tokens[i], address(redemptionOperator), amounts[i]);
        }
    }

    function _assertOperatorDust(address[6] memory tokens, uint256[6] memory amounts)
        internal
        view
    {
        for (uint256 i = 0; i < tokens.length; i++) {
            assertEq(IERC20(tokens[i]).balanceOf(address(redemptionOperator)), amounts[i]);
        }
    }

    function _assertIntegrationAllowances(uint256 expected) internal view {
        assertEq(
            IERC20(redemptionOperator.usdc()).allowance(
                address(redemptionOperator),
                redemptionOperator.frxUsdCustodian()
            ),
            expected
        );
        assertEq(
            IERC20(redemptionOperator.frxUsd()).allowance(
                address(redemptionOperator),
                redemptionOperator.frxUsdCustodian()
            ),
            expected
        );
        assertEq(
            IERC20(redemptionOperator.usdc()).allowance(
                address(redemptionOperator),
                redemptionOperator.morpho()
            ),
            expected
        );
    }
}
