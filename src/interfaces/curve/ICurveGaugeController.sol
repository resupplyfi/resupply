// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface ICurveGaugeController {
    function get_gauge_weight(address _pool) external returns (uint256);
    function vote_for_gauge_weights(address _gauge_addr, uint256 _user_weight) external;
    function add_gauge(address _gauge_addr, int128 _type) external;
    function admin() external view returns (address);
}