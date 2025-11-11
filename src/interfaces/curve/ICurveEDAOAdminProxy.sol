// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IController {
    function set_callback(address _cb) external;
    function set_amm_fee(uint256 _fee) external;
    function set_amm_admin_fee(uint256 _fee) external;
    function set_monetary_policy(address _monetary_policy) external;
    function set_borrowing_discounts(uint256 _loan_discount, uint256 _liquidation_discount) external;
}

interface IFactory {
    function set_admin(address admin) external;
    function set_debt_ceiling(address _to, uint256 debt_ceiling) external;
    function debt_ceiling(address _to) external view returns (uint256);
}


interface ICurveEDAOAdminProxy {
    function dao() external view returns (address);
    function emergency() external view returns (address);

    function set_callback(IController _controller, address _cb) external;
    function set_amm_fee(IController _controller, uint256 _fee) external;
    function set_monetary_policy(IController _controller, address _monetary_policy) external;
    function set_borrowing_discounts(IController _controller, uint256 _loan_discount, uint256 _liquidation_discount) external;
    function set_admin_fee(IController _controller, uint256 _fee) external;
    function reduce_debt_ceiling(IFactory _factory, address _to, uint256 _amount) external;
    function execute(address _target, bytes calldata _calldata) external payable returns (bytes memory);
    function transfer_ownership(IFactory _factory, address _owner) external;
    function set_emergency(address _emergency) external;
    function remove_emergency() external;
}