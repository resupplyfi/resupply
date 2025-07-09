// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/// @title Curve One-Way Lending Vault (Solidity interface)
/// @notice Mirrors the public / external surface of the Vyper `Vault`
///         implementation (v0.3.10). Used by integrators and factories.

interface ICurveLendingVault {
    /* ────────────────────────────── Events ───────────────────────────── */
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Transfer(address indexed sender, address indexed receiver, uint256 value);
    event Deposit(
        address indexed sender,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );
    event Withdraw(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    /* ───────────────────────── ERC-20 metadata ───────────────────────── */
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);

    /* ───────────────────────── ERC-20 standard ───────────────────────── */
    function totalSupply() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);

    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
    function increaseAllowance(address spender, uint256 addValue) external returns (bool);
    function decreaseAllowance(address spender, uint256 subValue) external returns (bool);

    /* ─────────────────────── Vault initialisation ────────────────────── */
    function initialize(
        address ammImpl,
        address controllerImpl,
        address borrowedToken,
        address collateralToken,
        uint256 A,
        uint256 fee,
        address priceOracle,
        address monetaryPolicy,
        uint256 loanDiscount,
        uint256 liquidationDiscount
    ) external returns (address controller, address amm);

    /* ──────────────── External view helpers / getters ────────────────── */
    function borrowed_token() external view returns (address);
    function collateral_token() external view returns (address);
    function price_oracle() external view returns (address);
    function amm() external view returns (address);
    function controller() external view returns (address);
    function factory() external view returns (address);

    function borrow_apr() external view returns (uint256);
    function lend_apr() external view returns (uint256);
    function asset() external view returns (address);
    function totalAssets() external view returns (uint256);
    function pricePerShare(bool isFloor) external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function maxDeposit(address receiver) external view returns (uint256);
    function previewDeposit(uint256 assets) external view returns (uint256);
    function maxMint(address receiver) external view returns (uint256);
    function previewMint(uint256 shares) external view returns (uint256);
    function maxWithdraw(address owner) external view returns (uint256);
    function previewWithdraw(uint256 assets) external view returns (uint256);
    function maxRedeem(address owner) external view returns (uint256);
    function previewRedeem(uint256 shares) external view returns (uint256);

    /* ──────────────────────── Core vault actions ─────────────────────── */
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function mint(uint256 shares, address receiver) external returns (uint256 assets);
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external returns (uint256 sharesBurned);
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256 assetsReturned);
}