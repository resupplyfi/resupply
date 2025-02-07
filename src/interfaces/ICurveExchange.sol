// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface ICurveExchange {

    function exchange(
        int128,
        int128,
        uint256,
        uint256,
        address
    ) external returns (uint256);

    function calc_token_amount(uint256[2] calldata _amounts, bool _isDeposit) external view returns(uint256);
    function calc_token_amount(uint256[2] calldata _amounts) external view returns(uint256);
    function calc_withdraw_one_coin(uint256 _amount, int128 _index) external view returns(uint256);
    function calc_withdraw_one_coin(uint256 _amount, uint256 _index) external view returns(uint256);
    function add_liquidity(uint256[] calldata _amounts, uint256 _min_mint_amount, address _receiver) external returns(uint256);
    // function add_liquidity(uint256[2] calldata _amounts, uint256 _min_mint_amount, bool _useEth, address _receiver) external returns(uint256);
    function remove_liquidity(uint256 _amount, uint256[2] calldata _min_amounts, address _receiver) external returns(uint256[2] calldata);
    function remove_liquidity_one_coin(uint256 _amount, int128 _index, uint256 _min_amount, address _receiver) external returns(uint256);
    function remove_liquidity_one_coin(uint256 _amount, uint256 _index, uint256 _min_amount, address _receiver) external returns(uint256);
    function remove_liquidity_one_coin(uint256 _amount, uint256 _index, uint256 _min_amount, bool _useEth, address _receiver) external returns(uint256);


    function deploy_plain_pool(string calldata _name,string calldata _symbol,address[] calldata _coins,uint256 _A,uint256 _fee,uint256 _offpeg_fee_multiplier,uint256 _ma_exp_time,uint256 _implementation_idx,uint8[] calldata _asset_types,bytes4[] calldata _method_ids,address[] calldata _oracles) external returns(address);
}