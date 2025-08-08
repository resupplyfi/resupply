// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface ICurveFactory {
    // Events
    event BasePoolAdded(address base_pool);
    event PlainPoolDeployed(
        address[] coins,
        uint256 A,
        uint256 fee,
        address deployer
    );
    event MetaPoolDeployed(
        address coin,
        address base_pool,
        uint256 A,
        uint256 fee,
        address deployer
    );
    event LiquidityGaugeDeployed(address pool, address gauge);

    // Structs
    struct PoolArray {
        address base_pool;
        address implementation;
        address liquidity_gauge;
        address[] coins;
        uint256[] decimals;
        uint256 n_coins;
        uint8[] asset_types;
    }

    struct BasePoolArray {
        address lp_token;
        address[] coins;
        uint256 decimals;
        uint256 n_coins;
        uint8[] asset_types;
    }

    // Factory Getters
    function find_pool_for_coins(
        address _from,
        address _to,
        uint256 i
    ) external view returns (address);

    // Pool Getters
    function get_base_pool(address _pool) external view returns (address);
    function get_n_coins(address _pool) external view returns (uint256);
    function get_meta_n_coins(address _pool) external view returns (uint256, uint256);
    function get_coins(address _pool) external view returns (address[] memory);
    function get_underlying_coins(address _pool) external view returns (address[] memory);
    function get_decimals(address _pool) external view returns (uint256[] memory);
    function get_underlying_decimals(address _pool) external view returns (uint256[] memory);
    function get_metapool_rates(address _pool) external view returns (uint256[] memory);
    function get_balances(address _pool) external view returns (uint256[] memory);
    function get_underlying_balances(address _pool) external view returns (uint256[] memory);
    function get_A(address _pool) external view returns (uint256);
    function get_fees(address _pool) external view returns (uint256, uint256);
    function get_admin_balances(address _pool) external view returns (uint256[] memory);
    function get_coin_indices(
        address _pool,
        address _from,
        address _to
    ) external view returns (int128, int128, bool);
    function get_gauge(address _pool) external view returns (address);
    function get_implementation_address(address _pool) external view returns (address);
    function is_meta(address _pool) external view returns (bool);
    function get_pool_asset_types(address _pool) external view returns (uint8[] memory);

    // Pool Deployers
    function deploy_plain_pool(
        string calldata _name,
        string calldata _symbol,
        address[] calldata _coins,
        uint256 _A,
        uint256 _fee,
        uint256 _offpeg_fee_multiplier,
        uint256 _ma_exp_time,
        uint256 _implementation_idx,
        uint8[] calldata _asset_types,
        bytes4[] calldata _method_ids,
        address[] calldata _oracles
    ) external returns (address);

    function deploy_metapool(
        address _base_pool,
        string calldata _name,
        string calldata _symbol,
        address _coin,
        uint256 _A,
        uint256 _fee,
        uint256 _offpeg_fee_multiplier,
        uint256 _ma_exp_time,
        uint256 _implementation_idx,
        uint8 _asset_type,
        bytes4 _method_id,
        address _oracle
    ) external returns (address);

    function deploy_gauge(address _pool) external returns (address);

    // Admin Functions
    function add_base_pool(
        address _base_pool,
        address _base_lp_token,
        uint8[] calldata _asset_types,
        uint256 _n_coins
    ) external;

    function set_pool_implementations(
        uint256 _implementation_index,
        address _implementation
    ) external;

    function set_metapool_implementations(
        uint256 _implementation_index,
        address _implementation
    ) external;

    function set_math_implementation(address _math_implementation) external;
    function set_gauge_implementation(address _gauge_implementation) external;
    function set_views_implementation(address _views_implementation) external;
    function commit_transfer_ownership(address _addr) external;
    function accept_transfer_ownership() external;
    function set_fee_receiver(address _pool, address _fee_receiver) external;
    function add_asset_type(uint8 _id, string calldata _name) external;

    // State Variables
    function admin() external view returns (address);
    function future_admin() external view returns (address);
    function asset_types(uint8) external view returns (string memory);
    function pool_list(uint256) external view returns (address);
    function pool_count() external view returns (uint256);
    function pool_data(address) external view returns (PoolArray memory);
    function base_pool_list(uint256) external view returns (address);
    function base_pool_count() external view returns (uint256);
    function base_pool_data(address) external view returns (BasePoolArray memory);
    function base_pool_assets(address) external view returns (bool);
    function pool_implementations(uint256) external view returns (address);
    function metapool_implementations(uint256) external view returns (address);
    function math_implementation() external view returns (address);
    function gauge_implementation() external view returns (address);
    function views_implementation() external view returns (address);
    function fee_receiver() external view returns (address);
    function markets(uint256, uint256) external view returns (address);
    function market_counts(uint256) external view returns (uint256);
}
