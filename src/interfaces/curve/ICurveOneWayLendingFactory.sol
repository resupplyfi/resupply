// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/// @title One-Way Lending Factory (Solidity interface)
/// @notice Interface mirroring the public / external surface of the Vyper
///         `OneWayLendingFactory` (version 0.3.10).

interface ICurveOneWayLendingFactory {
    /* ───────────────────────────── Events ─────────────────────────────── */
    event SetImplementations(
        address amm,
        address controller,
        address vault,
        address price_oracle,
        address monetary_policy,
        address gauge
    );
    event SetDefaultRates(uint256 min_rate, uint256 max_rate);
    event SetAdmin(address admin);
    event NewVault(
        uint256 indexed id,
        address indexed collateral_token,
        address indexed borrowed_token,
        address vault,
        address controller,
        address amm,
        address price_oracle,
        address monetary_policy
    );
    event LiquidityGaugeDeployed(address vault, address gauge);

    /* ───────────────────── Immutable / constant getters ───────────────── */
    function STABLECOIN() external view returns (address);
    function MIN_RATE() external pure returns (uint256);
    function MAX_RATE() external pure returns (uint256);

    /* ───────────────────────── Implementation refs ────────────────────── */
    function amm_impl() external view returns (address);
    function controller_impl() external view returns (address);
    function vault_impl() external view returns (address);
    function pool_price_oracle_impl() external view returns (address);
    function monetary_policy_impl() external view returns (address);
    function gauge_impl() external view returns (address);

    /* ───────────────────── Factory configuration getters ──────────────── */
    function min_default_borrow_rate() external view returns (uint256);
    function max_default_borrow_rate() external view returns (uint256);
    function admin() external view returns (address);

    /* ─────────────────────── Registry / lookup views ──────────────────── */
    function market_count() external view returns (uint256);
    function vaults(uint256) external view returns (address);
    function amms(uint256) external view returns (address);
    function gauges(uint256) external view returns (address);
    function token_to_vaults(address token, uint256 idx) external view returns (address);
    function token_market_count(address token) external view returns (uint256);
    function names(uint256 id) external view returns (string memory);

    function controllers(uint256 id) external view returns (address);
    function borrowed_tokens(uint256 id) external view returns (address);
    function collateral_tokens(uint256 id) external view returns (address);
    function price_oracles(uint256 id) external view returns (address);
    function monetary_policies(uint256 id) external view returns (address);
    function vaults_index(address vault) external view returns (uint256);

    function gauge_for_vault(address vault) external view returns (address);
    function coins(uint256 vaultId) external view returns (address[2] memory);

    /* ──────────────────────────── Mutative API ────────────────────────── */
    function create(
        address borrowed_token,
        address collateral_token,
        uint256 A,
        uint256 fee,
        uint256 loan_discount,
        uint256 liquidation_discount,
        address price_oracle,
        string calldata name,
        uint256 min_borrow_rate,
        uint256 max_borrow_rate
    ) external returns (address vault);

    function create_from_pool(
        address borrowed_token,
        address collateral_token,
        uint256 A,
        uint256 fee,
        uint256 loan_discount,
        uint256 liquidation_discount,
        address pool,
        string calldata name,
        uint256 min_borrow_rate,
        uint256 max_borrow_rate
    ) external returns (address vault);

    function deploy_gauge(address vault) external returns (address gauge);

    function set_implementations(
        address controller,
        address amm,
        address vault,
        address pool_price_oracle,
        address monetary_policy,
        address gauge
    ) external;

    function set_default_rates(uint256 min_rate, uint256 max_rate) external;
    function set_admin(address admin) external;
}