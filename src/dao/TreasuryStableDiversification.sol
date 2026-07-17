// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

interface ICurveStableSwapPool {
    function coins(uint256 index) external view returns (address);
    function price_oracle(uint256 index) external view returns (uint256);
    function last_prices(uint256 index) external view returns (uint256);
    function last_price(uint256 index) external view returns (uint256);
    function get_p(uint256 index) external view returns (uint256);
    function exchange(int128 i, int128 j, uint256 dx, uint256 minDy) external returns (uint256);
}

/// @notice Permissionless treasury stable diversification helper controlled by the owner.
contract TreasuryStableDiversification is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint16 internal constant FULL_BPS = 10_000;
    uint256 internal constant MAX_CURVE_COINS = 8;
    uint256 internal constant PRICE_PRECISION = 1e18;

    struct Target {
        address token;
        uint256 weight;
        address swapPool;
        address vault;
        address inputToken;
        address stakedAsset;
        // 18-decimal source stable value per target stable value. Zero uses the stable/PPS parity guard.
        uint256 maxPrice;
        uint16 maxSpotEmaDeviationBps;
        uint16 executionBufferBps;
    }

    // Lowercase public immutables match the getter style used by existing governance contracts.
    // forge-lint: disable-next-line(screaming-snake-case-immutable)
    address public immutable treasury;
    // forge-lint: disable-next-line(screaming-snake-case-immutable)
    address public immutable asset;
    // forge-lint: disable-next-line(screaming-snake-case-immutable)
    uint8 public immutable assetDecimals;

    Target[] internal _targets;
    uint256 public totalWeight;
    uint16 public maxDeviationBps;
    uint256 public minTreasuryAssetBalance;
    bool public useOperators;
    mapping(address => bool) public operators;

    error TreasuryStableDiversification_ZeroAddress();
    error TreasuryStableDiversification_NoTargets();
    error TreasuryStableDiversification_NoAssets();
    error TreasuryStableDiversification_InvalidTarget();
    error TreasuryStableDiversification_InvalidDeviation();
    error TreasuryStableDiversification_InvalidStakedAsset();
    error TreasuryStableDiversification_InvalidVaultAsset();
    error TreasuryStableDiversification_PoolCoinNotFound(address pool, address token);
    error TreasuryStableDiversification_InsufficientOutput(address token, uint256 minAmount, uint256 actualAmount);
    error TreasuryStableDiversification_NotOperator(address account);
    error TreasuryStableDiversification_InvalidOraclePrice(address pool);
    error TreasuryStableDiversification_OracleVolatile(uint256 emaPrice, uint256 spotPrice, uint256 maxDeviationBps);
    error TreasuryStableDiversification_PriceOutOfRange(uint256 spotPrice, uint256 maxPrice);

    event TargetsSet(uint256 count, uint256 totalWeight);
    event MaxDeviationBpsSet(uint16 maxDeviationBps);
    event MinTreasuryAssetBalanceSet(uint256 minTreasuryAssetBalance);
    event UseOperatorsSet(bool useOperators);
    event OperatorSet(address indexed operator, bool active);
    event SwapExecuted(uint256 requestedAmount, uint256 assetAmount);
    event TargetSwapped(
        uint256 indexed index,
        address indexed token,
        uint256 inputAmount,
        uint256 tokenAmount,
        address indexed vault,
        uint256 shares
    );
    event TokenRetrieved(address indexed token, address indexed to, uint256 amount);

    constructor(address owner_, address treasury_, address asset_, uint16 maxDeviationBps_) Ownable(owner_) {
        if (treasury_ == address(0) || asset_ == address(0)) revert TreasuryStableDiversification_ZeroAddress();
        treasury = treasury_;
        asset = asset_;
        assetDecimals = IERC20Metadata(asset_).decimals();
        _setMaxDeviationBps(maxDeviationBps_);
    }

    function targetCount() external view returns (uint256) {
        return _targets.length;
    }

    function targets(uint256 index) external view returns (Target memory) {
        return _targets[index];
    }

    function setMaxDeviationBps(uint16 newMaxDeviationBps) external onlyOwner {
        _setMaxDeviationBps(newMaxDeviationBps);
    }

    function setMinTreasuryAssetBalance(uint256 newMinTreasuryAssetBalance) external onlyOwner {
        minTreasuryAssetBalance = newMinTreasuryAssetBalance;
        emit MinTreasuryAssetBalanceSet(newMinTreasuryAssetBalance);
    }

    function setUseOperators(bool newUseOperators) external onlyOwner {
        useOperators = newUseOperators;
        emit UseOperatorsSet(newUseOperators);
    }

    function setOperator(address operator, bool active) external onlyOwner {
        if (operator == address(0)) revert TreasuryStableDiversification_ZeroAddress();
        operators[operator] = active;
        emit OperatorSet(operator, active);
    }

    function setTargets(Target[] calldata newTargets) external onlyOwner {
        delete _targets;

        uint256 nextTotalWeight;
        for (uint256 i; i < newTargets.length; ++i) {
            Target calldata target = newTargets[i];
            bool usesDefaultAsset = target.inputToken == address(0);
            if (target.token == address(0) || (usesDefaultAsset && target.weight == 0)) {
                revert TreasuryStableDiversification_InvalidTarget();
            }
            address inputToken = usesDefaultAsset ? asset : target.inputToken;
            if (target.stakedAsset != address(0)) {
                if (IERC4626(target.stakedAsset).asset() != inputToken) {
                    revert TreasuryStableDiversification_InvalidStakedAsset();
                }
                inputToken = target.stakedAsset;
            }
            if (target.token != inputToken && target.swapPool == address(0)) {
                revert TreasuryStableDiversification_InvalidTarget();
            }
            if (target.maxSpotEmaDeviationBps > FULL_BPS || target.executionBufferBps > FULL_BPS) {
                revert TreasuryStableDiversification_InvalidDeviation();
            }
            if (target.maxPrice != 0 && (target.swapPool == address(0) || target.token == inputToken)) {
                revert TreasuryStableDiversification_InvalidTarget();
            }
            if (target.vault != address(0) && IERC4626(target.vault).asset() != target.token) {
                revert TreasuryStableDiversification_InvalidVaultAsset();
            }
            if (target.vault != address(0) && _targetTokenFeedsLaterInput(newTargets, i, target.token)) {
                revert TreasuryStableDiversification_InvalidTarget();
            }

            if (usesDefaultAsset) nextTotalWeight += target.weight;
            _targets.push(target);
        }

        totalWeight = nextTotalWeight;
        emit TargetsSet(newTargets.length, nextTotalWeight);
    }

    function swap(uint256 amount) external nonReentrant returns (uint256 assetAmount) {
        if (useOperators && !operators[msg.sender]) revert TreasuryStableDiversification_NotOperator(msg.sender);

        uint256 length = _targets.length;
        if (length == 0) revert TreasuryStableDiversification_NoTargets();

        IERC20 assetToken = IERC20(asset);
        if (amount != 0) {
            uint256 treasuryBalance = assetToken.balanceOf(treasury);
            uint256 treasuryExcess =
                treasuryBalance > minTreasuryAssetBalance ? treasuryBalance - minTreasuryAssetBalance : 0;
            uint256 pullAmount = amount < treasuryExcess ? amount : treasuryExcess;
            if (pullAmount != 0) assetToken.safeTransferFrom(treasury, address(this), pullAmount);
        }

        assetAmount = assetToken.balanceOf(address(this));
        if (assetAmount == 0) revert TreasuryStableDiversification_NoAssets();

        uint256 remainingAssets = assetAmount;
        uint256 configuredTotalWeight = totalWeight;
        uint256 lastDefaultAssetTarget = _lastDefaultAssetTarget(length);
        for (uint256 i; i < length; ++i) {
            Target memory target = _targets[i];
            address sourceToken = target.inputToken == address(0) ? asset : target.inputToken;
            uint256 sourceAmount;
            if (target.inputToken == address(0)) {
                sourceAmount = i == lastDefaultAssetTarget
                    ? remainingAssets
                    : Math.mulDiv(assetAmount, target.weight, configuredTotalWeight);
                remainingAssets -= sourceAmount;
            } else {
                sourceAmount = IERC20(sourceToken).balanceOf(address(this));
            }
            address inputToken = sourceToken;
            uint256 swapInputAmount = sourceAmount;
            if (target.stakedAsset != address(0)) {
                inputToken = target.stakedAsset;
                uint256 existingShares = IERC20(inputToken).balanceOf(address(this));
                uint256 newShares = sourceAmount == 0 ? 0 : _stakeAsset(IERC20(sourceToken), target.stakedAsset, sourceAmount);
                swapInputAmount = existingShares + newShares;
            }
            if (swapInputAmount == 0) continue;
            uint256 minOut = _minTargetAmount(target, inputToken, swapInputAmount);

            uint256 received = target.token == inputToken
                ? swapInputAmount
                : _swapViaCurve(IERC20(inputToken), inputToken, target, swapInputAmount, minOut);
            if (received < minOut) {
                revert TreasuryStableDiversification_InsufficientOutput(target.token, minOut, received);
            }

            uint256 shares;
            uint256 targetAmount = received;
            if (!_isInputForLaterTarget(i, target.token)) {
                targetAmount = IERC20(target.token).balanceOf(address(this));
                shares = _returnOrDeposit(target.token, target.vault, targetAmount);
            }
            emit TargetSwapped(i, target.token, sourceAmount, targetAmount, target.vault, shares);
        }

        emit SwapExecuted(amount, assetAmount);
    }

    function retrieveToken(address token, address to) external onlyOwner {
        if (token == address(0) || to == address(0)) revert TreasuryStableDiversification_ZeroAddress();
        retrieveTokenExact(token, to, IERC20(token).balanceOf(address(this)));
    }

    function retrieveTokenExact(address token, address to, uint256 amount) public onlyOwner {
        if (token == address(0) || to == address(0)) revert TreasuryStableDiversification_ZeroAddress();
        IERC20(token).safeTransfer(to, amount);
        emit TokenRetrieved(token, to, amount);
    }

    function _setMaxDeviationBps(uint16 newMaxDeviationBps) internal {
        if (newMaxDeviationBps > FULL_BPS) revert TreasuryStableDiversification_InvalidDeviation();
        maxDeviationBps = newMaxDeviationBps;
        emit MaxDeviationBpsSet(newMaxDeviationBps);
    }

    function _stakeAsset(IERC20 assetToken, address stakedAsset_, uint256 amount) internal returns (uint256 shares) {
        assetToken.forceApprove(stakedAsset_, amount);
        shares = IERC4626(stakedAsset_).deposit(amount, address(this));
        assetToken.forceApprove(stakedAsset_, 0);
    }

    function _swapViaCurve(
        IERC20 inputToken,
        address inputTokenAddress,
        Target memory target,
        uint256 inputAmount,
        uint256 minOut
    ) internal returns (uint256 received) {
        int128 assetIndex = _curveCoinIndex(target.swapPool, inputTokenAddress);
        int128 targetIndex = _curveCoinIndex(target.swapPool, target.token);
        uint256 balanceBefore = IERC20(target.token).balanceOf(address(this));

        inputToken.forceApprove(target.swapPool, inputAmount);
        ICurveStableSwapPool(target.swapPool).exchange(assetIndex, targetIndex, inputAmount, minOut);
        inputToken.forceApprove(target.swapPool, 0);

        received = IERC20(target.token).balanceOf(address(this)) - balanceBefore;
    }

    function _returnOrDeposit(address token, address vault, uint256 amount) internal returns (uint256 shares) {
        if (vault == address(0)) {
            IERC20(token).safeTransfer(treasury, amount);
            return 0;
        }

        IERC20(token).forceApprove(vault, amount);
        shares = IERC4626(vault).deposit(amount, treasury);
        IERC20(token).forceApprove(vault, 0);
    }

    function _minTargetAmount(Target memory target, address sourceToken, uint256 sourceAmount)
        internal
        view
        returns (uint256)
    {
        if (target.maxSpotEmaDeviationBps != 0) {
            _requireCurvePriceGuard(target, sourceToken);
        }
        if (target.maxPrice != 0) {
            if (target.maxSpotEmaDeviationBps == 0) _requireCurvePriceGuard(target, sourceToken);
            uint256 pricedTargetAmount =
                _targetAmountAtMaxPrice(target.token, sourceToken, sourceAmount, target.maxPrice);
            return Math.mulDiv(pricedTargetAmount, FULL_BPS - uint256(target.executionBufferBps), FULL_BPS);
        }

        uint256 targetAmount = _targetAmountForInput(target.token, sourceToken, sourceAmount);
        return Math.mulDiv(targetAmount, FULL_BPS - uint256(maxDeviationBps), FULL_BPS);
    }

    function _targetAmountForInput(address targetToken, address sourceToken, uint256 sourceAmount)
        internal
        view
        returns (uint256)
    {
        (uint256 stableAmount, uint8 stableDecimals) = _stableAmountForToken(sourceToken, sourceAmount);
        return _tokenAmountForStableValue(targetToken, stableAmount, stableDecimals);
    }

    function _targetAmountAtMaxPrice(address targetToken, address sourceToken, uint256 sourceAmount, uint256 maxPrice)
        internal
        view
        returns (uint256)
    {
        (uint256 stableAmount, uint8 stableDecimals) = _stableAmountForToken(sourceToken, sourceAmount);
        uint256 sourceStable18 = _scaleAmount(stableAmount, stableDecimals, 18);
        uint256 targetStable18 = Math.mulDiv(sourceStable18, PRICE_PRECISION, maxPrice);
        return _tokenAmountForStableValue(targetToken, targetStable18, 18);
    }

    function _tokenAmountForStableValue(address token, uint256 stableAmount, uint8 stableDecimals)
        internal
        view
        returns (uint256)
    {
        try IERC4626(token).asset() returns (address vaultAsset) {
            uint256 vaultAssetAmount = _scaleAmount(stableAmount, stableDecimals, _tokenDecimals(vaultAsset));
            try IERC4626(token).convertToShares(vaultAssetAmount) returns (uint256 shares) {
                return shares;
            } catch {}
        } catch {}

        return _scaleAmount(stableAmount, stableDecimals, _tokenDecimals(token));
    }

    function _stableAmountForToken(address token, uint256 amount) internal view returns (uint256, uint8) {
        try IERC4626(token).asset() returns (address vaultAsset) {
            try IERC4626(token).convertToAssets(amount) returns (uint256 assets) {
                return (assets, _tokenDecimals(vaultAsset));
            } catch {}
        } catch {}

        return (amount, _tokenDecimals(token));
    }

    function _tokenDecimals(address token) internal view returns (uint8) {
        return token == asset ? assetDecimals : IERC20Metadata(token).decimals();
    }

    function _scaleAmount(uint256 amount, uint8 fromDecimals, uint8 toDecimals) internal pure returns (uint256) {
        if (fromDecimals == toDecimals) return amount;
        if (fromDecimals < toDecimals) return amount * 10 ** (toDecimals - fromDecimals);
        return amount / 10 ** (fromDecimals - toDecimals);
    }

    function _requireCurvePriceGuard(Target memory target, address inputToken) internal view {
        uint256 spotPrice = _normalizedCurvePrice(target, inputToken, _curveSpotRawPrice(target.swapPool));
        uint256 emaPrice = _normalizedCurvePrice(target, inputToken, _curveEmaRawPrice(target.swapPool));
        if (_deviationBps(emaPrice, spotPrice) > target.maxSpotEmaDeviationBps) {
            revert TreasuryStableDiversification_OracleVolatile(emaPrice, spotPrice, target.maxSpotEmaDeviationBps);
        }
        if (target.maxPrice != 0 && spotPrice > target.maxPrice) {
            revert TreasuryStableDiversification_PriceOutOfRange(spotPrice, target.maxPrice);
        }
    }

    function _normalizedCurvePrice(Target memory target, address inputToken, uint256 rawPrice)
        internal
        view
        returns (uint256)
    {
        if (rawPrice == 0) revert TreasuryStableDiversification_InvalidOraclePrice(target.swapPool);
        int128 inputIndex = _curveCoinIndex(target.swapPool, inputToken);
        int128 targetIndex = _curveCoinIndex(target.swapPool, target.token);
        // Curve NG oracle/spot prices are already rate-adjusted via stored_rates.
        // ERC4626 PPS conversion belongs in min-out sizing, not in oracle normalization.
        uint256 inputAmount18;
        if (inputIndex == 0 && targetIndex == 1) {
            inputAmount18 = rawPrice;
        } else if (inputIndex == 1 && targetIndex == 0) {
            inputAmount18 = Math.mulDiv(PRICE_PRECISION, PRICE_PRECISION, rawPrice, Math.Rounding.Ceil);
        } else {
            revert TreasuryStableDiversification_InvalidOraclePrice(target.swapPool);
        }
        return inputAmount18;
    }

    function _curveSpotRawPrice(address pool) internal view returns (uint256) {
        try ICurveStableSwapPool(pool).last_prices(0) returns (uint256 price) {
            if (price != 0) return price;
        } catch {}

        try ICurveStableSwapPool(pool).last_price(0) returns (uint256 price) {
            if (price != 0) return price;
        } catch {}

        try ICurveStableSwapPool(pool).get_p(0) returns (uint256 price) {
            if (price != 0) return price;
        } catch {}

        revert TreasuryStableDiversification_InvalidOraclePrice(pool);
    }

    function _curveEmaRawPrice(address pool) internal view returns (uint256) {
        try ICurveStableSwapPool(pool).price_oracle(0) returns (uint256 price) {
            if (price != 0) return price;
        } catch {}

        revert TreasuryStableDiversification_InvalidOraclePrice(pool);
    }

    function _deviationBps(uint256 referencePrice, uint256 observedPrice) internal pure returns (uint256) {
        if (referencePrice == 0) return type(uint256).max;
        uint256 diff = referencePrice > observedPrice ? referencePrice - observedPrice : observedPrice - referencePrice;
        return Math.mulDiv(diff, FULL_BPS, referencePrice);
    }

    function _curveCoinIndex(address pool, address token) internal view returns (int128) {
        int128 index;
        for (uint256 i; i < MAX_CURVE_COINS; ++i) {
            try ICurveStableSwapPool(pool).coins(i) returns (address coin) {
                if (coin == token) return index;
            } catch {
                break;
            }
            ++index;
        }
        revert TreasuryStableDiversification_PoolCoinNotFound(pool, token);
    }

    function _lastDefaultAssetTarget(uint256 length) internal view returns (uint256 lastIndex) {
        lastIndex = type(uint256).max;
        for (uint256 i; i < length; ++i) {
            if (_targets[i].inputToken == address(0)) lastIndex = i;
        }
    }

    function _targetTokenFeedsLaterInput(Target[] calldata newTargets, uint256 index, address token)
        internal
        pure
        returns (bool)
    {
        for (uint256 i = index + 1; i < newTargets.length; ++i) {
            if (newTargets[i].inputToken == token) return true;
        }
        return false;
    }

    function _isInputForLaterTarget(uint256 index, address token) internal view returns (bool) {
        uint256 length = _targets.length;
        for (uint256 i = index + 1; i < length; ++i) {
            if (_targets[i].inputToken == token) return true;
        }
        return false;
    }
}
