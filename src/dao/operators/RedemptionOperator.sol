// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC3156FlashBorrower } from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import { IERC3156FlashLender } from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";

import { ICurveExchange } from "src/interfaces/curve/ICurveExchange.sol";
import { IERC4626 } from "src/interfaces/IERC4626.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IRedemptionHandler } from "src/interfaces/IRedemptionHandler.sol";
import { IFraxLoan } from "src/interfaces/IFraxLoan.sol";
import { IFraxLoanCallback } from "src/interfaces/IFraxLoanCallback.sol";

contract RedemptionOperator is ReentrancyGuard, IERC3156FlashBorrower, IFraxLoanCallback {
    using SafeERC20 for IERC20;

    bytes32 private constant FLASH_CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    address public constant registry = 0x10101010E0C3171D894B71B3400668aF311e7D94;
    address public constant reusd = 0x57aB1E0003F623289CD798B1824Be09a793e4Bec;
    address public constant treasury = 0x4444444455bF42de586A88426E5412971eA48324;
    address public constant crvUsd = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
    address public constant frxUsd = 0xCAcd6fd266aF91b8AeD52aCCc382b4e165586E29;
    address public constant sCrvUsd = 0x0655977FEb2f289A4aB78af67BAB0d17aAb84367;
    address public constant sFrxUsd = 0xcf62F905562626CfcDD2261162a51fd02Fc9c5b6;
    address public constant crvUsdFlashLender = 0x26dE7861e213A5351F6ED767d00e0839930e9eE1;
    address public constant frxUsdFlashLender = 0xeeb6b2Feef7BeDb28b9Fa70E1724ea5FC37d42AB;
    address public constant reusdScrvPool = 0xc522A6606BBA746d7960404F22a3DB936B6F4F50;
    address public constant reusdSfrxPool = 0xed785Af60bEd688baa8990cD5c4166221599A441;
    address public constant frxusdSfrxusdPool = 0xF292eB6c5dcb693Eaaf392D0562a01C3710E5978;
    uint256 public immutable reusdDust;

    int128 public immutable scrvIndex;
    int128 public immutable reusdIndexScrv;
    int128 public immutable sfrxIndex;
    int128 public immutable reusdIndexSfrx;
    int128 public immutable frxusdIndexFraxPool;
    int128 public immutable sfrxusdIndexFraxPool;

    bool private inFlash;
    uint256 public lastProfit;
    address public owner;
    mapping(address => bool) public approvedCallers;

    event CallerApproved(address indexed account, bool status);
    event Swept(address indexed token, address indexed to, uint256 amount);

    constructor(uint256 _reusdDust) {
        reusdDust = _reusdDust;
        owner = msg.sender;
        approvedCallers[msg.sender] = true;
        (scrvIndex, reusdIndexScrv) = _resolveIndices(reusdScrvPool, sCrvUsd, reusd);
        (sfrxIndex, reusdIndexSfrx) = _resolveIndices(reusdSfrxPool, sFrxUsd, reusd);
        (frxusdIndexFraxPool, sfrxusdIndexFraxPool) = _resolveIndices(frxusdSfrxusdPool, frxUsd, sFrxUsd);
        _setApprovals();
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    modifier onlyApproved() {
        require(approvedCallers[msg.sender], "caller !approved");
        _;
    }

    function setApprovedCaller(address account, bool status) external onlyOwner {
        require(account != address(0), "invalid account");
        approvedCallers[account] = status;
        emit CallerApproved(account, status);
    }

    function executeRedemption(
        address bestPair,
        uint256 flashAmount,
        uint256 minReusdFromSwap,
        uint256 minProfit,
        uint256 maxFeePct
    ) external nonReentrant onlyApproved returns (uint256 profit) {
        require(!inFlash, "flash active");
        require(flashAmount != 0, "invalid flash amount");
        require(IERC20(reusd).balanceOf(address(this)) <= reusdDust, "leftover reusd");

        IResupplyPair pair = IResupplyPair(bestPair);
        address flashAsset = pair.underlying();
        require(_isSupportedAsset(flashAsset), "invalid flash asset");

        uint256 minRedemption = pair.minimumRedemption();
        uint256 maxRedeemable = IRedemptionHandler(_redemptionHandler()).getMaxRedeemableDebt(bestPair);
        require(maxRedeemable >= minRedemption, "insufficient redeemable");
        require(minReusdFromSwap >= minRedemption, "min reusd too low");
        require(minReusdFromSwap <= maxRedeemable, "min reusd too high");

        inFlash = true;

        bytes memory data = abi.encode(
            bestPair,
            flashAsset,
            flashAmount,
            minReusdFromSwap,
            minProfit,
            maxFeePct
        );
        if (flashAsset == crvUsd) {
            IERC3156FlashLender(crvUsdFlashLender).flashLoan(
                IERC3156FlashBorrower(address(this)),
                flashAsset,
                flashAmount,
                data
            );
        } else {
            IFraxLoan(frxUsdFlashLender).getFraxloan(flashAsset, flashAmount, data);
        }

        require(!inFlash, "flash active");
        profit = lastProfit;
    }

    function isProfitable(uint256 flashAmount)
        external
        view
        returns (bool profitable, uint256 profit, address bestPair, uint256 redeemAmount)
    {
        if (flashAmount == 0) {
            return (false, 0, address(0), 0);
        }
        uint256 maxCrvFlash = IERC3156FlashLender(crvUsdFlashLender).maxFlashLoan(crvUsd);
        bool crvAllowed = flashAmount <= maxCrvFlash;
        bool frxAllowed = IERC20(frxUsd).balanceOf(frxUsdFlashLender) >= flashAmount;

        address[] memory pairs = IResupplyRegistry(registry).getAllPairAddresses();
        uint256 length = pairs.length;
        address handler = _redemptionHandler();

        for (uint256 i = 0; i < length; i++) {
            address pair = pairs[i];
            address flashAsset = IResupplyPair(pair).underlying();
            if (!_isSupportedAsset(flashAsset)) continue;
            if (flashAsset == crvUsd && !crvAllowed) continue;
            if (flashAsset == frxUsd && !frxAllowed) continue;

            uint256 maxRedeemable = IRedemptionHandler(handler).getMaxRedeemableDebt(pair);
            if (maxRedeemable == 0) continue;

            uint256 expectedReusd;
            if (flashAsset == frxUsd) {
                uint256 sfrxOut = ICurveExchange(frxusdSfrxusdPool).get_dy(
                    frxusdIndexFraxPool,
                    sfrxusdIndexFraxPool,
                    flashAmount
                );
                expectedReusd = ICurveExchange(reusdSfrxPool).get_dy(
                    sfrxIndex,
                    reusdIndexSfrx,
                    sfrxOut
                );
            } else {
                (address pool, address vault, int128 vaultIndex, int128 reusdIndex) = _poolConfig(flashAsset);
                uint256 shares = IERC4626(vault).previewDeposit(flashAmount);
                expectedReusd = ICurveExchange(pool).get_dy(vaultIndex, reusdIndex, shares);
            }
            if (expectedReusd == 0) continue;
            if (expectedReusd > maxRedeemable) continue;
            if (expectedReusd < IResupplyPair(pair).minimumRedemption()) continue;

            (uint256 expectedUnderlying,,) = IRedemptionHandler(handler).previewRedeem(pair, expectedReusd);
            if (expectedUnderlying == 0) continue;

            uint256 feeEstimate = _flashFeeEstimate(flashAsset, flashAmount);
            if (expectedUnderlying <= flashAmount + feeEstimate) continue;
            uint256 candidateProfit = expectedUnderlying - flashAmount - feeEstimate;
            if (candidateProfit > profit) {
                profit = candidateProfit;
                bestPair = pair;
                redeemAmount = expectedReusd;
            }
        }

        profitable = profit > 0;
    }

    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external override returns (bytes32) {
        require(msg.sender == crvUsdFlashLender, "invalid callback caller");
        require(initiator == address(this), "invalid callback caller");
        require(token == crvUsd, "invalid token");
        _handleFlashCallback(token, amount, fee, data, true);
        return FLASH_CALLBACK_SUCCESS;
    }

    function onFraxLoan(address asset, uint256 amount, bytes calldata data) external override {
        require(msg.sender == frxUsdFlashLender, "invalid callback caller");
        require(asset == frxUsd, "invalid token");
        uint256 fee = _fraxFee(amount);
        _handleFlashCallback(asset, amount, fee, data, false);
    }

    function _handleFlashCallback(
        address asset,
        uint256 amount,
        uint256 fee,
        bytes calldata data,
        bool useCrvUsd
    ) internal {
        require(inFlash, "flash inactive");
        (
            address pair,
            address assetExpected,
            uint256 amountExpected,
            uint256 minReusdFromSwap,
            uint256 minProfit,
            uint256 maxFeePct
        ) = abi.decode(data, (address, address, uint256, uint256, uint256, uint256));
        require(asset == assetExpected && amount == amountExpected, "invalid callback data");

        uint256 reusdOut;
        if (useCrvUsd) {
            (address pool, address vault, int128 vaultIndex, int128 reusdIndex) = _poolConfig(asset);
            uint256 shares = IERC4626(vault).deposit(amount, address(this));

            reusdOut = ICurveExchange(pool).exchange(
                vaultIndex,
                reusdIndex,
                shares,
                minReusdFromSwap,
                address(this)
            );
        } else {
            uint256 sfrxOut = ICurveExchange(frxusdSfrxusdPool).exchange(
                frxusdIndexFraxPool,
                sfrxusdIndexFraxPool,
                amount,
                0,
                address(this)
            );

            reusdOut = ICurveExchange(reusdSfrxPool).exchange(
                sfrxIndex,
                reusdIndexSfrx,
                sfrxOut,
                minReusdFromSwap,
                address(this)
            );
        }

        uint256 redeemAmount;
        uint256 underlyingFromRedeem;
        uint256 minRedemption = IResupplyPair(pair).minimumRedemption();
        address handler = _redemptionHandler();
        uint256 maxRedeemable = IRedemptionHandler(handler).getMaxRedeemableDebt(pair);

        require(reusdOut >= minRedemption, "redeem below min");
        require(reusdOut <= maxRedeemable, "redeem exceeds max");

        redeemAmount = reusdOut;
        underlyingFromRedeem = IRedemptionHandler(handler).redeemFromPair(
            pair,
            redeemAmount,
            maxFeePct,
            address(this),
            true
        );

        uint256 totalOwed = amount + fee;
        uint256 balance = IERC20(asset).balanceOf(address(this));
        require(balance >= totalOwed + minProfit, "not profitable");

        if (useCrvUsd) {
            // crvUSD flash lender expects push repayment (balance delta), not allowance pull.
            IERC20(asset).safeTransfer(crvUsdFlashLender, totalOwed);
        } else {
            IERC20(asset).safeTransfer(frxUsdFlashLender, totalOwed);
        }

        uint256 profit = balance - totalOwed;
        if (profit > 0) {
            IERC20(asset).safeTransfer(treasury, profit);
        }

        lastProfit = profit;
        inFlash = false;
    }

    function sweep(address token, address to, uint256 amount) external onlyOwner {
        require(!inFlash, "flash active");
        require(to != address(0), "invalid recipient");
        IERC20(token).safeTransfer(to, amount);
        emit Swept(token, to, amount);
    }

    function _flashFeeEstimate(address flashAsset, uint256 flashAmount) internal view returns (uint256) {
        if (flashAsset == crvUsd) {
            return IERC3156FlashLender(crvUsdFlashLender).flashFee(flashAsset, flashAmount);
        }

        if (IFraxLoan(frxUsdFlashLender).isExempt(address(this))) return 0;
        return IFraxLoan(frxUsdFlashLender).calcFee(flashAmount);
    }

    function _fraxFee(uint256 flashAmount) internal view returns (uint256) {
        if (IFraxLoan(frxUsdFlashLender).isExempt(address(this))) return 0;
        return IFraxLoan(frxUsdFlashLender).calcFee(flashAmount);
    }

    function _poolConfig(address flashAsset)
        internal
        view
        returns (address pool, address vault, int128 vaultIndex, int128 reusdIndex)
    {
        if (flashAsset == crvUsd) {
            return (reusdScrvPool, sCrvUsd, scrvIndex, reusdIndexScrv);
        }
        if (flashAsset == frxUsd) {
            return (reusdSfrxPool, sFrxUsd, sfrxIndex, reusdIndexSfrx);
        }
        require(false, "invalid flash asset");
    }

    function _resolveIndices(address pool, address vaultToken, address reusdToken)
        internal
        view
        returns (int128 vaultIndex, int128 reusdIndex)
    {
        address coin0 = ICurveExchange(pool).coins(0);
        address coin1 = ICurveExchange(pool).coins(1);
        if (coin0 == vaultToken && coin1 == reusdToken) return (0, 1);
        if (coin1 == vaultToken && coin0 == reusdToken) return (1, 0);
        require(false, "invalid flash asset");
    }

    function _isSupportedAsset(address flashAsset) internal view returns (bool) {
        return flashAsset == crvUsd || flashAsset == frxUsd;
    }

    function _redemptionHandler() internal view returns (address) {
        return IResupplyRegistry(registry).redemptionHandler();
    }

    function _setApprovals() internal {
        address handler = _redemptionHandler();

        IERC20(crvUsd).forceApprove(sCrvUsd, type(uint256).max);
        IERC20(sCrvUsd).forceApprove(reusdScrvPool, type(uint256).max);
        IERC20(reusd).forceApprove(reusdScrvPool, type(uint256).max);

        IERC20(frxUsd).forceApprove(frxusdSfrxusdPool, type(uint256).max);
        IERC20(sFrxUsd).forceApprove(reusdSfrxPool, type(uint256).max);
        IERC20(reusd).forceApprove(reusdSfrxPool, type(uint256).max);
        IERC20(sFrxUsd).forceApprove(frxusdSfrxusdPool, type(uint256).max);

        IERC20(reusd).forceApprove(handler, type(uint256).max);
    }
}
