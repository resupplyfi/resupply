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
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { BaseUpgradeableOperator } from "src/dao/operators/BaseUpgradeableOperator.sol";

contract RedemptionOperator is
    BaseUpgradeableOperator,
    ReentrancyGuardUpgradeable,
    IERC3156FlashBorrower,
    IMorphoFlashLoanCallback
{
    using SafeERC20 for IERC20;

    enum Route {
        Invalid,
        CrvUsdToCrvUsd,
        CrvUsdToFrxUsd,
        UsdcToFrxUsd
    }

    struct CallbackData {
        address caller;
        address pair;
        address loanAsset;
        uint256 flashAmount;
        uint256 minReusdFromSwap;
        uint256 minProfit;
        uint256 maxFeePct;
    }

    struct FundingQuote {
        uint256 crvFlashFee;
        uint256 reusdForCrvPair;
        uint256 reusdForFrxPair;
        uint256 frxForUsdc;
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

    event CallerApproved(address indexed account, bool status);
    event ManagerSet(address indexed manager);
    event RedemptionExecuted(
        address indexed caller,
        address indexed pair,
        address indexed loanAsset,
        uint256 flashAmount,
        uint256 reusdAmount,
        uint256 profit
    );
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
        _setApprovals();

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
        _setApprovals();
    }

    function revokeIntegrationApprovals() external onlyOwnerOrManager {
        IERC20(usdc).forceApprove(frxUsdCustodian, 0);
        IERC20(frxUsd).forceApprove(frxUsdCustodian, 0);
        IERC20(usdc).forceApprove(morpho, 0);
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

    /// @notice Executes one caller-selected redemption funding route.
    /// @param bestPair Pair to redeem against.
    /// @param loanAsset crvUSD or USDC flash-loan asset.
    /// @param flashAmount Amount to flash borrow in the loan asset's native units.
    /// @param minReusdFromSwap Minimum reUSD acquired before redemption.
    /// @param minProfit Minimum realized profit, denominated in crvUSD.
    /// @param maxFeePct Max redemption fee percentage (1e18 precision).
    function executeRedemption(
        address bestPair,
        address loanAsset,
        uint256 flashAmount,
        uint256 minReusdFromSwap,
        uint256 minProfit,
        uint256 maxFeePct
    ) external onlyApproved nonReentrant {
        require(flashAmount != 0, "invalid flash amount");
        require(minProfit != 0, "invalid min profit");

        Route route = _classifyRoute(loanAsset, IResupplyPair(bestPair).underlying());
        require(route != Route.Invalid, "unsupported route");

        bytes memory data = abi.encode(
            CallbackData({
                caller: msg.sender,
                pair: bestPair,
                loanAsset: loanAsset,
                flashAmount: flashAmount,
                minReusdFromSwap: minReusdFromSwap,
                minProfit: minProfit,
                maxFeePct: maxFeePct
            })
        );

        if (loanAsset == crvUsd) {
            bool success = IERC3156FlashLender(crvUsdFlashLender).flashLoan(
                IERC3156FlashBorrower(address(this)),
                crvUsd,
                flashAmount,
                data
            );
            require(success, "flash loan failed");
        } else {
            IMorpho(morpho).flashLoan(usdc, flashAmount, data);
        }
    }

    /// @notice Finds the most profitable pair for one explicit funding asset.
    /// @dev Profit is always denominated in crvUSD.
    function isProfitable(uint256 flashAmount, address loanAsset)
        public
        view
        returns (address bestPair, uint256 profit, uint256 redeemAmount)
    {
        if (flashAmount == 0) return (address(0), 0, 0);

        FundingQuote memory funding;

        if (loanAsset == crvUsd) {
            IERC3156FlashLender lender = IERC3156FlashLender(crvUsdFlashLender);
            if (lender.maxFlashLoan(crvUsd) < flashAmount) return (address(0), 0, 0);

            funding.crvFlashFee = lender.flashFee(crvUsd, flashAmount);
            funding.reusdForCrvPair = _quoteAcquisition(Route.CrvUsdToCrvUsd, flashAmount);
            funding.reusdForFrxPair = _quoteAcquisition(Route.CrvUsdToFrxUsd, flashAmount);
        } else if (loanAsset == usdc) {
            if (IERC20(usdc).balanceOf(morpho) < flashAmount) return (address(0), 0, 0);
            if (IERC4626(frxUsdCustodian).maxDeposit(address(this)) < flashAmount) {
                return (address(0), 0, 0);
            }

            funding.reusdForFrxPair = _quoteAcquisition(Route.UsdcToFrxUsd, flashAmount);
            funding.frxForUsdc = IERC4626(frxUsdCustodian).previewWithdraw(flashAmount);
        } else {
            return (address(0), 0, 0);
        }

        address[] memory pairs = IResupplyRegistry(registry).getAllPairAddresses();
        address handler = _redemptionHandler();

        for (uint256 i = 0; i < pairs.length; i++) {
            address pairAddress = pairs[i];
            (uint256 candidateProfit, uint256 reusdOut) =
                _quotePair(pairAddress, handler, loanAsset, flashAmount, funding);

            if (candidateProfit > profit) {
                bestPair = pairAddress;
                profit = candidateProfit;
                redeemAmount = reusdOut;
            }
        }
    }

    function _quotePair(
        address pairAddress,
        address handler,
        address loanAsset,
        uint256 flashAmount,
        FundingQuote memory funding
    ) internal view returns (uint256 candidateProfit, uint256 reusdOut) {
        IResupplyPair pair = IResupplyPair(pairAddress);
        Route route = _classifyRoute(loanAsset, pair.underlying());
        if (route == Route.Invalid) return (0, 0);

        reusdOut = route == Route.CrvUsdToCrvUsd
            ? funding.reusdForCrvPair
            : funding.reusdForFrxPair;
        if (reusdOut == 0 || reusdOut < pair.minimumRedemption()) return (0, 0);

        (uint256 underlyingOut, uint256 collateralShares,) =
            IRedemptionHandler(handler).previewRedeem(pairAddress, reusdOut);
        if (underlyingOut == 0) return (0, 0);
        if (collateralShares > IERC4626(pair.collateral()).maxRedeem(pairAddress)) return (0, 0);

        if (route == Route.UsdcToFrxUsd) {
            if (underlyingOut <= funding.frxForUsdc) return (0, 0);
            candidateProfit = ICurveExchange(crvUsdFrxUsdPool).get_dy(
                frxUsdIndexFrxPool,
                crvUsdIndexFrxPool,
                underlyingOut - funding.frxForUsdc
            );
            return (candidateProfit, reusdOut);
        }

        uint256 crvProceeds = underlyingOut;
        if (route == Route.CrvUsdToFrxUsd) {
            crvProceeds = ICurveExchange(crvUsdFrxUsdPool).get_dy(
                frxUsdIndexFrxPool,
                crvUsdIndexFrxPool,
                underlyingOut
            );
        }

        uint256 repayment = flashAmount + funding.crvFlashFee;
        if (crvProceeds <= repayment) return (0, 0);
        return (crvProceeds - repayment, reusdOut);
    }

    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external override returns (bytes32) {
        require(_reentrancyGuardEntered(), "inactive callback");
        require(msg.sender == crvUsdFlashLender, "invalid callback caller");
        require(initiator == address(this), "invalid initiator");
        require(token == crvUsd, "invalid token");

        CallbackData memory callbackData = abi.decode(data, (CallbackData));
        require(callbackData.loanAsset == token && callbackData.flashAmount == amount, "invalid callback data");
        _handleFlashCallback(callbackData, fee);
        return FLASH_CALLBACK_SUCCESS;
    }

    function onMorphoFlashLoan(uint256 assets, bytes calldata data) external override {
        require(_reentrancyGuardEntered(), "inactive callback");
        require(msg.sender == morpho, "invalid callback caller");

        CallbackData memory callbackData = abi.decode(data, (CallbackData));
        require(callbackData.loanAsset == usdc && callbackData.flashAmount == assets, "invalid callback data");
        _handleFlashCallback(callbackData, 0);
    }

    function _handleFlashCallback(CallbackData memory data, uint256 flashFee) internal {
        require(data.flashAmount != 0, "invalid flash amount");
        require(data.minProfit != 0, "invalid min profit");

        IResupplyPair pair = IResupplyPair(data.pair);
        Route route = _classifyRoute(data.loanAsset, pair.underlying());
        require(route != Route.Invalid, "unsupported route");

        uint256 reusdOut = _acquireReusd(route, data.flashAmount, data.minReusdFromSwap);
        require(reusdOut >= data.minReusdFromSwap, "insufficient reusd");
        require(reusdOut >= pair.minimumRedemption(), "redeem below min");

        uint256 underlyingOut = IRedemptionHandler(_redemptionHandler()).redeemFromPair(
            data.pair,
            reusdOut,
            data.maxFeePct,
            address(this),
            true
        );

        uint256 crvProceeds;
        if (route == Route.CrvUsdToCrvUsd) {
            crvProceeds = underlyingOut;
        } else if (route == Route.CrvUsdToFrxUsd) {
            crvProceeds = _swapFrxToCrv(underlyingOut);
        } else {
            uint256 frxBurned = IERC4626(frxUsdCustodian).withdraw(
                data.flashAmount,
                address(this),
                address(this)
            );
            require(underlyingOut >= frxBurned, "insufficient frxusd");

            uint256 frxSurplus = underlyingOut - frxBurned;
            if (frxSurplus != 0) crvProceeds = _swapFrxToCrv(frxSurplus);
        }

        uint256 profit;
        if (route == Route.UsdcToFrxUsd) {
            require(crvProceeds >= data.minProfit, "not profitable");
            profit = crvProceeds;
        } else {
            uint256 totalOwed = data.flashAmount + flashFee;
            require(crvProceeds >= totalOwed + data.minProfit, "not profitable");
            IERC20(crvUsd).safeTransfer(crvUsdFlashLender, totalOwed);
            profit = crvProceeds - totalOwed;
        }

        IERC20(crvUsd).safeTransfer(treasury, profit);
        emit RedemptionExecuted(
            data.caller,
            data.pair,
            data.loanAsset,
            data.flashAmount,
            reusdOut,
            profit
        );
    }

    function _quoteAcquisition(Route route, uint256 amount) internal view returns (uint256) {
        if (route == Route.CrvUsdToCrvUsd) {
            uint256 shares = IERC4626(sCrvUsd).previewDeposit(amount);
            return ICurveExchange(reusdScrvPool).get_dy(scrvIndex, reusdIndexScrv, shares);
        }

        uint256 frxAmount;
        if (route == Route.CrvUsdToFrxUsd) {
            frxAmount = ICurveExchange(crvUsdFrxUsdPool).get_dy(
                crvUsdIndexFrxPool,
                frxUsdIndexFrxPool,
                amount
            );
        } else if (route == Route.UsdcToFrxUsd) {
            frxAmount = IERC4626(frxUsdCustodian).previewDeposit(amount);
        } else {
            revert("unsupported route");
        }

        uint256 sfrxOut = ICurveExchange(frxusdSfrxusdPool).get_dy(
            frxusdIndexFraxPool,
            sfrxusdIndexFraxPool,
            frxAmount
        );
        return ICurveExchange(reusdSfrxPool).get_dy(sfrxIndex, reusdIndexSfrx, sfrxOut);
    }

    function _acquireReusd(Route route, uint256 amount, uint256 minReusdFromSwap)
        internal
        returns (uint256)
    {
        if (route == Route.CrvUsdToCrvUsd) {
            uint256 shares = IERC4626(sCrvUsd).deposit(amount, address(this));
            return ICurveExchange(reusdScrvPool).exchange(
                scrvIndex,
                reusdIndexScrv,
                shares,
                minReusdFromSwap,
                address(this)
            );
        }

        uint256 frxAmount;
        if (route == Route.CrvUsdToFrxUsd) {
            frxAmount = ICurveExchange(crvUsdFrxUsdPool).exchange(
                crvUsdIndexFrxPool,
                frxUsdIndexFrxPool,
                amount,
                0,
                address(this)
            );
        } else {
            frxAmount = IERC4626(frxUsdCustodian).deposit(amount, address(this));
        }

        uint256 sfrxOut = ICurveExchange(frxusdSfrxusdPool).exchange(
            frxusdIndexFraxPool,
            sfrxusdIndexFraxPool,
            frxAmount,
            0,
            address(this)
        );
        return ICurveExchange(reusdSfrxPool).exchange(
            sfrxIndex,
            reusdIndexSfrx,
            sfrxOut,
            minReusdFromSwap,
            address(this)
        );
    }

    function _swapFrxToCrv(uint256 amount) internal returns (uint256) {
        return ICurveExchange(crvUsdFrxUsdPool).exchange(
            frxUsdIndexFrxPool,
            crvUsdIndexFrxPool,
            amount,
            0,
            address(this)
        );
    }

    function _classifyRoute(address loanAsset, address pairUnderlying) internal pure returns (Route) {
        if (loanAsset == crvUsd) {
            if (pairUnderlying == crvUsd) return Route.CrvUsdToCrvUsd;
            if (pairUnderlying == frxUsd) return Route.CrvUsdToFrxUsd;
        } else if (loanAsset == usdc && pairUnderlying == frxUsd) {
            return Route.UsdcToFrxUsd;
        }
        return Route.Invalid;
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
    function approveRH() public {
        IERC20(reusd).forceApprove(_redemptionHandler(), type(uint256).max);
    }

    function _setApprovals() internal {
        IERC20(crvUsd).forceApprove(sCrvUsd, type(uint256).max);
        IERC20(sCrvUsd).forceApprove(reusdScrvPool, type(uint256).max);
        IERC20(reusd).forceApprove(reusdScrvPool, type(uint256).max);

        IERC20(frxUsd).forceApprove(frxusdSfrxusdPool, type(uint256).max);
        IERC20(sFrxUsd).forceApprove(reusdSfrxPool, type(uint256).max);
        IERC20(reusd).forceApprove(reusdSfrxPool, type(uint256).max);
        IERC20(sFrxUsd).forceApprove(frxusdSfrxusdPool, type(uint256).max);
        IERC20(crvUsd).forceApprove(crvUsdFrxUsdPool, type(uint256).max);
        IERC20(frxUsd).forceApprove(crvUsdFrxUsdPool, type(uint256).max);

        IERC20(usdc).forceApprove(frxUsdCustodian, type(uint256).max);
        IERC20(frxUsd).forceApprove(frxUsdCustodian, type(uint256).max);
        IERC20(usdc).forceApprove(morpho, type(uint256).max);

        approveRH();
    }
}
