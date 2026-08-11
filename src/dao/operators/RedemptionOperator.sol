// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC3156FlashBorrower } from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import { IERC3156FlashLender } from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import { ICurveExchange } from "src/interfaces/curve/ICurveExchange.sol";
import { IERC4626 } from "src/interfaces/IERC4626.sol";
import { IMorpho, IMorphoFlashLoanCallback } from "src/interfaces/IMorpho.sol";
import { IRedemptionHandler } from "src/interfaces/IRedemptionHandler.sol";
import { IRedemptionOperatorKeeper } from "src/interfaces/IRedemptionOperatorKeeper.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { BaseUpgradeableOperator } from "src/dao/operators/BaseUpgradeableOperator.sol";

contract RedemptionOperator is BaseUpgradeableOperator, ReentrancyGuardUpgradeable, IERC3156FlashBorrower, IMorphoFlashLoanCallback, IRedemptionOperatorKeeper {
    using SafeERC20 for IERC20;

    uint8 internal constant ROUTE_NONE = 0;
    uint8 internal constant ROUTE_CRVUSD_TO_CRVUSD = 1;
    uint8 internal constant ROUTE_CRVUSD_TO_FRXUSD = 2;
    uint8 internal constant ROUTE_USDC_TO_FRXUSD = 3;

    uint256 internal constant USDC_WAD_SCALE = 1e12;

    struct CallbackData {
        address caller;
        address pair;
        uint8 routeId;
        uint256 loanAmount;
        uint256 minReusdFromSwap;
        uint256 minProfit;
        uint256 maxFeePct;
    }

    struct FundingQuote {
        bool available;
        uint8 routeId;
        uint256 loanAmount;
        uint256 redeemAmount;
        uint256 settlementAmount;
    }

    struct FundingQuotes {
        FundingQuote crvToCrv;
        FundingQuote crvToFrx;
        FundingQuote usdcToFrx;
    }

    struct RedemptionQuote {
        bool available;
        uint256 underlyingAmount;
        uint256 collateralShares;
    }

    struct BestQuote {
        address pair;
        uint256 expectedProfit;
        uint256 redeemAmount;
        uint8 routeId;
        address loanAsset;
        uint256 loanAmount;
    }

    bytes32 private constant FLASH_CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    address public constant registry = 0x10101010E0C3171D894B71B3400668aF311e7D94;
    address public constant reusd = 0x57aB1E0003F623289CD798B1824Be09a793e4Bec;
    address public constant treasury = 0x4444444455bF42de586A88426E5412971eA48324;
    address public constant crvUsd = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
    address public constant frxUsd = 0xCAcd6fd266aF91b8AeD52aCCc382b4e165586E29;
    address public constant usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant sCrvUsd = 0x0655977FEb2f289A4aB78af67BAB0d17aAb84367;
    address public constant sFrxUsd = 0xcf62F905562626CfcDD2261162a51fd02Fc9c5b6;
    address public constant crvUsdFlashLender = 0x26dE7861e213A5351F6ED767d00e0839930e9eE1;
    address public constant morpho = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address public constant frxUsdCustodian = 0x4F95C5bA0C7c69FB2f9340E190cCeE890B3bd87c;
    address public constant reusdScrvPool = 0xc522A6606BBA746d7960404F22a3DB936B6F4F50;
    address public constant reusdSfrxPool = 0xed785Af60bEd688baa8990cD5c4166221599A441;
    address public constant frxusdSfrxusdPool = 0xF292eB6c5dcb693Eaaf392D0562a01C3710E5978;
    address public constant crvUsdFrxUsdPool = 0x13e12BB0E6A2f1A3d6901a59a9d585e89A6243e1;

    // Token indices
    int128 public constant scrvIndex = 1;
    int128 public constant reusdIndexScrv = 0;
    int128 public constant sfrxIndex = 1;
    int128 public constant reusdIndexSfrx = 0;
    int128 public constant frxusdIndexFraxPool = 1;
    int128 public constant sfrxusdIndexFraxPool = 0;
    int128 public constant crvUsdIndexFrxPool = 1;
    int128 public constant frxUsdIndexFrxPool = 0;

    mapping(address => bool) public approvedCallers;
    address public manager;
    bytes32 private activeCallbackHash;

    event CallerApproved(address indexed account, bool status);
    event ManagerSet(address indexed manager);
    event RedemptionExecuted(address indexed caller, address indexed pair, uint8 indexed routeId, address loanAsset, uint256 loanAmount, uint256 reusdAmount, uint256 profit);
    event Swept(address indexed token, address indexed to, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    modifier onlyApproved() {
        require(approvedCallers[msg.sender], "caller !approved");
        _;
    }

    modifier onlyOwnerOrManager() {
        require(msg.sender == manager || msg.sender == owner(), "!authorized");
        _;
    }

    function initialize(address _manager, address[] calldata _callers) external initializer {
        require(_manager != address(0), "invalid manager");
        __ReentrancyGuard_init();
        _setApprovals(type(uint256).max);

        manager = _manager;
        emit ManagerSet(_manager);

        uint256 length = _callers.length;
        for (uint256 i = 0; i < length; i++) {
            address caller = _callers[i];
            require(caller != address(0), "invalid account");
            approvedCallers[caller] = true;
            emit CallerApproved(caller, true);
        }
    }

    function setApprovals() external onlyOwnerOrManager {
        _setApprovals(type(uint256).max);
    }

    function revokeAllApprovals() external onlyOwnerOrManager {
        _setApprovals(0);
    }

    function setManager(address _manager) external onlyOwner {
        require(_manager != address(0), "invalid manager");
        manager = _manager;
        emit ManagerSet(_manager);
    }

    function setApprovedCaller(address _caller, bool _status) external onlyOwnerOrManager {
        require(_caller != address(0), "invalid account");
        approvedCallers[_caller] = _status;
        emit CallerApproved(_caller, _status);
    }

    /// @notice Executes exactly one previously quoted redemption route.
    /// @param bestPair Pair returned by `isProfitable`.
    /// @param routeId Append-only route identifier returned by `isProfitable`.
    /// @param loanAmount Native-unit loan amount returned by `isProfitable`.
    /// @param minReusdFromSwap Minimum reUSD acquired before redemption.
    /// @param minProfit Minimum realized profit, denominated in crvUSD.
    /// @param maxFeePct Max redemption fee percentage (1e18 precision).
    function executeRedemption(address bestPair, uint8 routeId, uint256 loanAmount, uint256 minReusdFromSwap, uint256 minProfit, uint256 maxFeePct) external override onlyApproved nonReentrant {
        require(loanAmount != 0, "invalid loan amount");
        require(minProfit != 0, "invalid min profit");
        require(activeCallbackHash == bytes32(0), "execution active");

        (address loanAsset, address lender, address pairUnderlying) = _routeConfiguration(routeId);
        require(IResupplyPair(bestPair).underlying() == pairUnderlying, "incompatible pair");

        bytes memory data = abi.encode(CallbackData({ caller: msg.sender, pair: bestPair, routeId: routeId, loanAmount: loanAmount, minReusdFromSwap: minReusdFromSwap, minProfit: minProfit, maxFeePct: maxFeePct }));
        activeCallbackHash = keccak256(data);

        if (lender == crvUsdFlashLender) {
            bool success = IERC3156FlashLender(lender).flashLoan(IERC3156FlashBorrower(address(this)), loanAsset, loanAmount, data);
            require(success, "flash loan failed");
        } else {
            IMorpho(lender).flashLoan(loanAsset, loanAmount, data);
        }
        require(activeCallbackHash == bytes32(0), "callback not executed");
    }

    /// @notice Finds the globally most profitable route and pair for a stablecoin notional.
    /// @dev Profit is crvUSD-denominated. Loan amount is returned in the loan asset's native units.
    function isProfitable(uint256 notionalWad) external view override returns (address bestPair, uint256 expectedProfit, uint256 redeemAmount, uint8 routeId, address loanAsset, uint256 loanAmount) {
        if (notionalWad == 0) return (address(0), 0, 0, ROUTE_NONE, address(0), 0);

        FundingQuotes memory funding = _quoteFundingRoutes(notionalWad);
        BestQuote memory best;

        address[] memory pairs = IResupplyRegistry(registry).getAllPairAddresses();
        address handler = _redemptionHandler();

        for (uint256 i = 0; i < pairs.length; i++) {
            address pairAddress = pairs[i];
            IResupplyPair pair = IResupplyPair(pairAddress);
            address underlying = pair.underlying();

            if (underlying == crvUsd && funding.crvToCrv.available) {
                best = _scoreCrvUsdPair(best, pairAddress, pair, handler, funding.crvToCrv);
            } else if (underlying == frxUsd) {
                best = _scoreFrxUsdPair(best, pairAddress, pair, handler, funding);
            }
        }

        return (best.pair, best.expectedProfit, best.redeemAmount, best.routeId, best.loanAsset, best.loanAmount);
    }

    function _quoteFundingRoutes(uint256 notionalWad) internal view returns (FundingQuotes memory funding) {
        IERC3156FlashLender crvLender = IERC3156FlashLender(crvUsdFlashLender);
        if (crvLender.maxFlashLoan(crvUsd) >= notionalWad) {
            uint256 repaymentAmount = notionalWad + crvLender.flashFee(crvUsd, notionalWad);
            uint256 crvPairRedeem = _quoteAcquisition(ROUTE_CRVUSD_TO_CRVUSD, notionalWad);
            uint256 frxPairRedeem = _quoteAcquisition(ROUTE_CRVUSD_TO_FRXUSD, notionalWad);

            funding.crvToCrv = FundingQuote({ available: crvPairRedeem != 0, routeId: ROUTE_CRVUSD_TO_CRVUSD, loanAmount: notionalWad, redeemAmount: crvPairRedeem, settlementAmount: repaymentAmount });
            funding.crvToFrx = FundingQuote({ available: frxPairRedeem != 0, routeId: ROUTE_CRVUSD_TO_FRXUSD, loanAmount: notionalWad, redeemAmount: frxPairRedeem, settlementAmount: repaymentAmount });
        }

        uint256 usdcLoanAmount = notionalWad / USDC_WAD_SCALE;
        if (usdcLoanAmount != 0 && IERC20(usdc).balanceOf(morpho) >= usdcLoanAmount && IERC4626(frxUsdCustodian).maxDeposit(address(this)) >= usdcLoanAmount) {
            uint256 redeemAmount = _quoteAcquisition(ROUTE_USDC_TO_FRXUSD, usdcLoanAmount);
            if (redeemAmount == 0) return funding;

            uint256 frxUsdForRepayment = IERC4626(frxUsdCustodian).previewWithdraw(usdcLoanAmount);
            funding.usdcToFrx = FundingQuote({ available: frxUsdForRepayment != 0, routeId: ROUTE_USDC_TO_FRXUSD, loanAmount: usdcLoanAmount, redeemAmount: redeemAmount, settlementAmount: frxUsdForRepayment });
        }
    }

    function _scoreCrvUsdPair(BestQuote memory best, address pairAddress, IResupplyPair pair, address handler, FundingQuote memory funding) internal view returns (BestQuote memory) {
        uint256 minimumRedemption = pair.minimumRedemption();
        RedemptionQuote memory redemption = _previewRedemption(pairAddress, handler, funding, minimumRedemption);
        if (!redemption.available) return best;

        uint256 maxCollateralRedeem = IERC4626(pair.collateral()).maxRedeem(pairAddress);
        if (redemption.collateralShares > maxCollateralRedeem) return best;
        return _score(best, pairAddress, funding, redemption.underlyingAmount);
    }

    function _scoreFrxUsdPair(BestQuote memory best, address pairAddress, IResupplyPair pair, address handler, FundingQuotes memory funding) internal view returns (BestQuote memory) {
        if (!funding.crvToFrx.available && !funding.usdcToFrx.available) return best;

        uint256 minimumRedemption = pair.minimumRedemption();
        RedemptionQuote memory crvRedemption = _previewRedemption(pairAddress, handler, funding.crvToFrx, minimumRedemption);
        RedemptionQuote memory usdcRedemption = _previewRedemption(pairAddress, handler, funding.usdcToFrx, minimumRedemption);
        if (!crvRedemption.available && !usdcRedemption.available) return best;

        uint256 maxCollateralRedeem = IERC4626(pair.collateral()).maxRedeem(pairAddress);
        if (crvRedemption.available && crvRedemption.collateralShares <= maxCollateralRedeem) {
            best = _score(best, pairAddress, funding.crvToFrx, crvRedemption.underlyingAmount);
        }
        if (usdcRedemption.available && usdcRedemption.collateralShares <= maxCollateralRedeem) {
            best = _score(best, pairAddress, funding.usdcToFrx, usdcRedemption.underlyingAmount);
        }
        return best;
    }

    function _previewRedemption(address pair, address handler, FundingQuote memory funding, uint256 minimumRedemption) internal view returns (RedemptionQuote memory redemption) {
        if (!funding.available || funding.redeemAmount < minimumRedemption) return redemption;

        (redemption.underlyingAmount, redemption.collateralShares,) = IRedemptionHandler(handler).previewRedeem(pair, funding.redeemAmount);
        redemption.available = redemption.underlyingAmount != 0;
    }

    function _score(BestQuote memory best, address pair, FundingQuote memory funding, uint256 underlyingAmount) internal view returns (BestQuote memory) {
        uint256 candidateProfit = _quoteProfit(funding, underlyingAmount);
        if (candidateProfit == 0) return best;
        if (candidateProfit < best.expectedProfit || (candidateProfit == best.expectedProfit && best.routeId != ROUTE_NONE && funding.routeId >= best.routeId)) return best;

        best.pair = pair;
        best.expectedProfit = candidateProfit;
        best.redeemAmount = funding.redeemAmount;
        best.routeId = funding.routeId;
        best.loanAsset = _loanAsset(funding.routeId);
        best.loanAmount = funding.loanAmount;
        return best;
    }

    function _quoteProfit(FundingQuote memory funding, uint256 underlyingAmount) internal view returns (uint256) {
        if (funding.routeId == ROUTE_USDC_TO_FRXUSD) {
            if (underlyingAmount <= funding.settlementAmount) return 0;
            return ICurveExchange(crvUsdFrxUsdPool).get_dy(frxUsdIndexFrxPool, crvUsdIndexFrxPool, underlyingAmount - funding.settlementAmount);
        }

        uint256 crvUsdProceeds = underlyingAmount;
        if (funding.routeId == ROUTE_CRVUSD_TO_FRXUSD) {
            crvUsdProceeds = ICurveExchange(crvUsdFrxUsdPool).get_dy(frxUsdIndexFrxPool, crvUsdIndexFrxPool, underlyingAmount);
        }
        if (crvUsdProceeds <= funding.settlementAmount) return 0;
        return crvUsdProceeds - funding.settlementAmount;
    }

    function onFlashLoan(address initiator, address token, uint256 amount, uint256 fee, bytes calldata data) external override returns (bytes32) {
        _requireActiveCallback();

        CallbackData memory callbackData = abi.decode(data, (CallbackData));
        require(callbackData.routeId == ROUTE_CRVUSD_TO_CRVUSD || callbackData.routeId == ROUTE_CRVUSD_TO_FRXUSD, "invalid callback route");
        (address expectedAsset, address expectedLender,) = _routeConfiguration(callbackData.routeId);
        require(msg.sender == expectedLender, "invalid callback caller");
        require(initiator == address(this), "invalid initiator");
        require(token == expectedAsset, "invalid token");
        require(callbackData.loanAmount == amount, "invalid callback amount");
        _consumeCallback(data);
        _handleFlashCallback(callbackData, fee);
        return FLASH_CALLBACK_SUCCESS;
    }

    function onMorphoFlashLoan(uint256 assets, bytes calldata data) external override {
        _requireActiveCallback();

        CallbackData memory callbackData = abi.decode(data, (CallbackData));
        require(callbackData.routeId == ROUTE_USDC_TO_FRXUSD, "invalid callback route");
        (, address expectedLender,) = _routeConfiguration(callbackData.routeId);
        require(msg.sender == expectedLender, "invalid callback caller");
        require(callbackData.loanAmount == assets, "invalid callback amount");
        _consumeCallback(data);
        _handleFlashCallback(callbackData, 0);
    }

    function _handleFlashCallback(CallbackData memory data, uint256 flashFee) internal {
        require(data.loanAmount != 0, "invalid loan amount");
        require(data.minProfit != 0, "invalid min profit");

        IResupplyPair pair = IResupplyPair(data.pair);
        (address loanAsset,, address pairUnderlying) = _routeConfiguration(data.routeId);
        require(pair.underlying() == pairUnderlying, "incompatible pair");

        uint256 reusdOut = _acquireReusd(data.routeId, data.loanAmount, data.minReusdFromSwap);
        require(reusdOut >= data.minReusdFromSwap, "insufficient reusd");
        require(reusdOut >= pair.minimumRedemption(), "redeem below min");

        uint256 underlyingOut = IRedemptionHandler(_redemptionHandler()).redeemFromPair(data.pair, reusdOut, data.maxFeePct, address(this), true);

        uint256 crvProceeds;
        if (data.routeId == ROUTE_CRVUSD_TO_CRVUSD) {
            crvProceeds = underlyingOut;
        } else if (data.routeId == ROUTE_CRVUSD_TO_FRXUSD) {
            crvProceeds = _swapFrxToCrv(underlyingOut);
        } else {
            uint256 frxBurned = IERC4626(frxUsdCustodian).withdraw(data.loanAmount, address(this), address(this));
            require(underlyingOut >= frxBurned, "insufficient frxusd");

            uint256 frxSurplus = underlyingOut - frxBurned;
            if (frxSurplus != 0) crvProceeds = _swapFrxToCrv(frxSurplus);
        }

        uint256 profit;
        if (data.routeId == ROUTE_USDC_TO_FRXUSD) {
            require(crvProceeds >= data.minProfit, "not profitable");
            profit = crvProceeds;
        } else {
            uint256 totalOwed = data.loanAmount + flashFee;
            require(crvProceeds >= totalOwed + data.minProfit, "not profitable");
            IERC20(crvUsd).safeTransfer(crvUsdFlashLender, totalOwed);
            profit = crvProceeds - totalOwed;
        }

        IERC20(crvUsd).safeTransfer(treasury, profit);
        emit RedemptionExecuted(data.caller, data.pair, data.routeId, loanAsset, data.loanAmount, reusdOut, profit);
    }

    function _requireActiveCallback() internal view {
        require(_reentrancyGuardEntered() && activeCallbackHash != bytes32(0), "inactive callback");
    }

    function _consumeCallback(bytes calldata data) internal {
        require(keccak256(data) == activeCallbackHash, "invalid callback data");
        activeCallbackHash = bytes32(0);
    }

    function _quoteAcquisition(uint8 routeId, uint256 amount) internal view returns (uint256) {
        if (routeId == ROUTE_CRVUSD_TO_CRVUSD) {
            uint256 shares = IERC4626(sCrvUsd).previewDeposit(amount);
            if (shares == 0) return 0;
            return ICurveExchange(reusdScrvPool).get_dy(scrvIndex, reusdIndexScrv, shares);
        }

        uint256 frxAmount;
        if (routeId == ROUTE_CRVUSD_TO_FRXUSD) {
            frxAmount = ICurveExchange(crvUsdFrxUsdPool).get_dy(crvUsdIndexFrxPool, frxUsdIndexFrxPool, amount);
        } else if (routeId == ROUTE_USDC_TO_FRXUSD) {
            frxAmount = IERC4626(frxUsdCustodian).previewDeposit(amount);
        } else {
            revert("unsupported route");
        }
        if (frxAmount == 0) return 0;

        uint256 sfrxOut = ICurveExchange(frxusdSfrxusdPool).get_dy(frxusdIndexFraxPool, sfrxusdIndexFraxPool, frxAmount);
        if (sfrxOut == 0) return 0;
        return ICurveExchange(reusdSfrxPool).get_dy(sfrxIndex, reusdIndexSfrx, sfrxOut);
    }

    function _acquireReusd(uint8 routeId, uint256 amount, uint256 minReusdFromSwap) internal returns (uint256) {
        if (routeId == ROUTE_CRVUSD_TO_CRVUSD) {
            uint256 shares = IERC4626(sCrvUsd).deposit(amount, address(this));
            return ICurveExchange(reusdScrvPool).exchange(scrvIndex, reusdIndexScrv, shares, minReusdFromSwap, address(this));
        }

        uint256 frxAmount;
        if (routeId == ROUTE_CRVUSD_TO_FRXUSD) {
            frxAmount = ICurveExchange(crvUsdFrxUsdPool).exchange(crvUsdIndexFrxPool, frxUsdIndexFrxPool, amount, 0, address(this));
        } else if (routeId == ROUTE_USDC_TO_FRXUSD) {
            frxAmount = IERC4626(frxUsdCustodian).deposit(amount, address(this));
        } else {
            revert("unsupported route");
        }

        uint256 sfrxOut = ICurveExchange(frxusdSfrxusdPool).exchange(frxusdIndexFraxPool, sfrxusdIndexFraxPool, frxAmount, 0, address(this));
        return ICurveExchange(reusdSfrxPool).exchange(sfrxIndex, reusdIndexSfrx, sfrxOut, minReusdFromSwap, address(this));
    }

    function _swapFrxToCrv(uint256 amount) internal returns (uint256) {
        return ICurveExchange(crvUsdFrxUsdPool).exchange(frxUsdIndexFrxPool, crvUsdIndexFrxPool, amount, 0, address(this));
    }

    function _loanAsset(uint8 routeId) internal pure returns (address) {
        if (routeId == ROUTE_CRVUSD_TO_CRVUSD || routeId == ROUTE_CRVUSD_TO_FRXUSD) {
            return crvUsd;
        }
        if (routeId == ROUTE_USDC_TO_FRXUSD) return usdc;
        revert("unsupported route");
    }

    function _routeConfiguration(uint8 routeId) internal pure returns (address loanAsset, address lender, address pairUnderlying) {
        if (routeId == ROUTE_CRVUSD_TO_CRVUSD) {
            return (crvUsd, crvUsdFlashLender, crvUsd);
        }
        if (routeId == ROUTE_CRVUSD_TO_FRXUSD) {
            return (crvUsd, crvUsdFlashLender, frxUsd);
        }
        if (routeId == ROUTE_USDC_TO_FRXUSD) {
            return (usdc, morpho, frxUsd);
        }
        revert("unsupported route");
    }

    function sweep(address token, address to, uint256 amount) external onlyOwnerOrManager {
        require(to != address(0), "invalid recipient");
        IERC20(token).safeTransfer(to, amount);
        emit Swept(token, to, amount);
    }

    function _redemptionHandler() internal view returns (address) {
        return IResupplyRegistry(registry).redemptionHandler();
    }

    // Approve current RH. Useful if address changes.
    function approveRH() public onlyOwnerOrManager {
        IERC20(reusd).forceApprove(_redemptionHandler(), type(uint256).max);
    }

    function _setApprovals(uint256 amount) internal {
        IERC20(crvUsd).forceApprove(sCrvUsd, amount);
        IERC20(sCrvUsd).forceApprove(reusdScrvPool, amount);
        IERC20(reusd).forceApprove(reusdScrvPool, amount);

        IERC20(frxUsd).forceApprove(frxusdSfrxusdPool, amount);
        IERC20(sFrxUsd).forceApprove(reusdSfrxPool, amount);
        IERC20(reusd).forceApprove(reusdSfrxPool, amount);
        IERC20(sFrxUsd).forceApprove(frxusdSfrxusdPool, amount);
        IERC20(crvUsd).forceApprove(crvUsdFrxUsdPool, amount);
        IERC20(frxUsd).forceApprove(crvUsdFrxUsdPool, amount);

        IERC20(usdc).forceApprove(frxUsdCustodian, amount);
        IERC20(frxUsd).forceApprove(frxUsdCustodian, amount);
        IERC20(usdc).forceApprove(morpho, amount);

        IERC20(reusd).forceApprove(_redemptionHandler(), amount);
    }
}
