// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC3156FlashBorrower } from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import { IERC3156FlashLender } from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import { ICurveExchange } from "src/interfaces/curve/ICurveExchange.sol";
import { IERC4626 } from "src/interfaces/IERC4626.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IRedemptionHandler } from "src/interfaces/IRedemptionHandler.sol";
import { IFraxLoan, IFraxLoanCallback } from "src/interfaces/IFraxLoan.sol";
import { BaseUpgradeableOperator } from "src/dao/operators/BaseUpgradeableOperator.sol";

contract RedemptionOperator is BaseUpgradeableOperator, ReentrancyGuardUpgradeable, IERC3156FlashBorrower, IFraxLoanCallback {
    using SafeERC20 for IERC20;

    bytes32 private constant FLASH_CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    uint256 public constant MIN_FLASH = 5_000e18;
    uint256 public constant MIN_PROFIT = 5e18;

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

    constructor() {_disableInitializers();}

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

    function setApprovals() external {
        _setApprovals();
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


    /// @notice Approved-only redemption with caller-supplied parameters.
    /// @param bestPair Pair to redeem against.
    /// @param flashAmount Amount to flash borrow for the attempt.
    /// @param minReusdFromSwap Minimum reUSD out from the Curve swap.
    /// @param minProfit Minimum profit required in the borrowed asset.
    /// @param maxFeePct Max redemption fee percentage (1e18 precision).
    function executeRedemption(
        address bestPair,
        uint256 flashAmount,
        uint256 minReusdFromSwap,
        uint256 minProfit,
        uint256 maxFeePct
    ) external onlyApproved nonReentrant {
        require(flashAmount != 0, "invalid flash amount");

        IResupplyPair pair = IResupplyPair(bestPair);
        address underlyingAsset = pair.underlying();
        address loanAsset = underlyingAsset;
        if (underlyingAsset == frxUsd) {
            uint256 frxAvailable = IERC20(frxUsd).balanceOf(frxUsdFlashLender);
            if (flashAmount > frxAvailable) {
                loanAsset = crvUsd;
            }
        }

        bytes memory data = abi.encode(
            msg.sender,
            bestPair,
            underlyingAsset,
            loanAsset,
            flashAmount,
            minReusdFromSwap,
            minProfit,
            maxFeePct
        );
        if (loanAsset == crvUsd) {
            IERC3156FlashLender(crvUsdFlashLender).flashLoan(
                IERC3156FlashBorrower(address(this)),
                loanAsset,
                flashAmount,
                data
            );
        } else {
            IFraxLoan(frxUsdFlashLender).getFraxloan(loanAsset, flashAmount, data);
        }
    }

    /// @notice Simulates profitability across all pairs for a flash amount.
    /// @param flashAmount Amount to flash borrow for simulation.
    /// @return bestPair Pair with the highest expected profit.
    /// @return profit Expected profit for the best pair.
    /// @return redeemAmount Expected reUSD redeem amount for the best pair.
    function isProfitable(uint256 flashAmount)
        public
        view
        returns (address bestPair, uint256 profit, uint256 redeemAmount)
    {
        if (flashAmount == 0) {
            return (address(0), 0, 0);
        }
        uint256 maxCrvFlash = IERC3156FlashLender(crvUsdFlashLender).maxFlashLoan(crvUsd);
        bool crvAllowed = flashAmount <= maxCrvFlash;
        bool frxAllowed = IERC20(frxUsd).balanceOf(frxUsdFlashLender) >= flashAmount;

        address[] memory pairs = IResupplyRegistry(registry).getAllPairAddresses();
        uint256 length = pairs.length;
        address handler = _redemptionHandler();

        for (uint256 i = 0; i < length; i++) {
            address pair = pairs[i];
            address underlyingAsset = IResupplyPair(pair).underlying();
            address loanAsset = underlyingAsset;
            if (underlyingAsset == crvUsd) {
                if (!crvAllowed) continue;
            } else if (underlyingAsset == frxUsd) {
                if (frxAllowed) {
                    loanAsset = frxUsd;
                } else if (crvAllowed) {
                    loanAsset = crvUsd;
                } else {
                    continue;
                }
            } else {
                continue;
            }

            uint256 maxRedeemable = IRedemptionHandler(handler).getMaxRedeemableDebt(pair);
            if (maxRedeemable == 0) continue;

            uint256 reusdOut;
            if (underlyingAsset == frxUsd) {
                uint256 frxAmount = flashAmount;
                if (loanAsset == crvUsd) {
                    frxAmount = ICurveExchange(crvUsdFrxUsdPool).get_dy(
                        crvUsdIndexFrxPool,
                        frxUsdIndexFrxPool,
                        flashAmount
                    );
                }
                uint256 sfrxOut = ICurveExchange(frxusdSfrxusdPool).get_dy(
                    frxusdIndexFraxPool,
                    sfrxusdIndexFraxPool,
                    frxAmount
                );
                reusdOut = ICurveExchange(reusdSfrxPool).get_dy(
                    sfrxIndex,
                    reusdIndexSfrx,
                    sfrxOut
                );
            } else {
                (address pool, address vault, int128 vaultIndex, int128 reusdIndex) = _poolConfig(underlyingAsset);
                uint256 shares = IERC4626(vault).previewDeposit(flashAmount);
                reusdOut = ICurveExchange(pool).get_dy(vaultIndex, reusdIndex, shares);
            }
            if (reusdOut == 0) continue;
            if (reusdOut > maxRedeemable) continue;
            if (reusdOut < IResupplyPair(pair).minimumRedemption()) continue;

            (uint256 expectedUnderlying,,) = IRedemptionHandler(handler).previewRedeem(pair, reusdOut);
            if (expectedUnderlying == 0) continue;

            uint256 grossUnderlying = expectedUnderlying;
            if (underlyingAsset == frxUsd && loanAsset == crvUsd) {
                grossUnderlying = ICurveExchange(crvUsdFrxUsdPool).get_dy(
                    frxUsdIndexFrxPool,
                    crvUsdIndexFrxPool,
                    expectedUnderlying
                );
            }

            uint256 feeEstimate = _flashFeeEstimate(loanAsset, flashAmount);
            if (grossUnderlying <= flashAmount + feeEstimate) continue;
            profit = grossUnderlying - flashAmount - feeEstimate;
            if (profit > 0) {
                bestPair = pair;
                redeemAmount = reusdOut;
            }
        }
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
        _handleFlashCallback(token, amount, fee, data);
        return FLASH_CALLBACK_SUCCESS;
    }

    function onFraxLoan(address asset, uint256 amount, bytes calldata data) external override {
        require(msg.sender == frxUsdFlashLender, "invalid callback caller");
        require(asset == frxUsd, "invalid token");
        uint256 fee = _fraxFee(amount);
        _handleFlashCallback(asset, amount, fee, data);
    }

    function _handleFlashCallback(address asset, uint256 amount, uint256 fee, bytes calldata data) internal {
        (
            address caller,
            address pair,
            address assetExpected,
            address loanAsset,
            uint256 amountExpected,
            uint256 minReusdFromSwap,
            uint256 minProfit,
            uint256 maxFeePct
        ) = abi.decode(data, (address, address, address, address, uint256, uint256, uint256, uint256));
        require(asset == loanAsset && amount == amountExpected, "invalid callback data");

        uint256 reusdOut;
        uint256 swapInputAmount = amount;
        if (loanAsset == crvUsd && assetExpected == frxUsd) {
            swapInputAmount = ICurveExchange(crvUsdFrxUsdPool).exchange(
                crvUsdIndexFrxPool,
                frxUsdIndexFrxPool,
                amount,
                0,
                address(this)
            );
        }

        if (assetExpected == crvUsd) {
            (address pool, address vault, int128 vaultIndex, int128 reusdIndex) = _poolConfig(assetExpected);
            uint256 shares = IERC4626(vault).deposit(swapInputAmount, address(this));
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
                swapInputAmount,
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
        if (loanAsset == crvUsd && assetExpected == frxUsd) {
            underlyingFromRedeem = ICurveExchange(crvUsdFrxUsdPool).exchange(
                frxUsdIndexFrxPool,
                crvUsdIndexFrxPool,
                underlyingFromRedeem,
                0,
                address(this)
            );
        }

        uint256 totalOwed = amount + fee;
        uint256 balance = IERC20(asset).balanceOf(address(this));
        require(balance >= totalOwed + minProfit, "not profitable");

        if (asset == crvUsd) {
            // crvUSD flash lender expects push repayment (balance delta), not allowance pull.
            IERC20(asset).safeTransfer(crvUsdFlashLender, totalOwed);
        } else {
            IERC20(asset).safeTransfer(frxUsdFlashLender, totalOwed);
        }

        uint256 profit = balance - totalOwed;
        if (profit > 0) {
            IERC20(asset).safeTransfer(treasury, profit);
        }

        emit RedemptionExecuted(
            caller,
            pair,
            loanAsset,
            amount,
            redeemAmount,
            profit
        );
    }

    function sweep(address token, address to, uint256 amount) external onlyOwner {
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

    function _redemptionHandler() internal view returns (address) {
        return IResupplyRegistry(registry).redemptionHandler();
    }

    // Approve current RH. Useful if address changes.
    function approveRH() external {
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

        // approve current RH
        IERC20(reusd).forceApprove(_redemptionHandler(), type(uint256).max);
    }

}
