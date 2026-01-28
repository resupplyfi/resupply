// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ICurveOracle } from "src/interfaces/curve/ICurveOracle.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IRedemptionHandler } from "src/interfaces/IRedemptionHandler.sol";

//oracle to query reusd price in terms of crvusd and/or usd
contract ReusdOracle {
   
    address public constant registry = address(0x10101010E0C3171D894B71B3400668aF311e7D94);
    address public constant crvusd = address(0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E);
    address public constant crvusd_oracle = address(0x18672b1b0c623a30089A280Ed9256379fb0E4E62);
    address public constant reusd_scrvusd_pool = address(0xc522A6606BBA746d7960404F22a3DB936B6F4F50);
    address public constant reusd_sfrxusd_pool = address(0xed785Af60bEd688baa8990cD5c4166221599A441);

    // Config Data
    uint8 internal constant DECIMALS = 18;
    string public name;
    uint256 public constant oracleType = 3;

    constructor(
        string memory _name
    ) {
        name = _name;
    }

    /// @notice The ```_reusdToCrvusd``` function returns price of reusd as crvusd
    /// @return _price is price of reusd in terms of crvusd
    function _reusdToCrvusd() internal view returns(uint256 _price){
        //get crvusd ema price from amm pool
        //note that even though the pool is scrvusd, price oracle returns price in crvusd
        _price = ICurveOracle(reusd_scrvusd_pool).price_oracle(0);
        //convert price from reusd per crvusd to crvusd per reusd
        _price = 1e36 / _price;
    }

    /// @notice The ```_reusdToFrxusd``` function returns price of reusd as frxusd
    /// @return _price is price of reusd in terms of frxusd
    function _reusdToFrxusd() internal view returns(uint256 _price){
        //get sfrxusd ema price from amm pool
        //note that even though the pool is sfrxusd, price oracle returns price in frxusd
        _price = ICurveOracle(reusd_sfrxusd_pool).price_oracle(0);
        //convert price from reusd per frxusd to frxusd per reusd
        _price = 1e36 / _price;
    }

    /// @notice The ```price``` function returns the price of reusd
    /// @return _price is usd price of reusd
    function price() external view returns (uint256 _price) {
        //price of reusd in terms of crvusd
        _price = _reusdToCrvusd();
        _price = _clamp(_price);
        //convert crvusd price to usd using crvusd's aggregate oracle
        uint256 aggprice = ICurveOracle(crvusd_oracle).price();
        _price = _price * aggprice / 1e18;
    }

    /// @notice The ```priceAsCrvusd``` function returns the price of reusd as crvusd
    /// @return _price is price of reusd in terms of crvusd
    function priceAsCrvusd() external view returns (uint256 _price) {
        //price of reusd in terms of crvusd
        _price = _reusdToCrvusd();
        _price = _clamp(_price);
    }

    /// @notice The ```priceAsFrxusd``` function returns the price of reusd as crvusd
    /// @return _price is price of reusd in terms of frxusd
    function priceAsFrxusd() external view returns (uint256 _price) {
        //price of reusd in terms of crvusd
        _price = _reusdToFrxusd();
        _price = _clamp(_price);
    }

    /// @notice Returns the price of reusd as crvusd without redemption fee clamp
    /// @return _price is price of reusd in terms of crvusd without redemption fee clamp
    function rawPriceAsCrvusd() external view returns (uint256 _price) {
        //price of reusd in terms of crvusd
        _price = _reusdToCrvusd();
    }

    function _clamp(uint256 _price) internal view returns (uint256) {
        //get redemption base fee
        //fee could be less than base via discounts but assume discounts are 0
        address rhandler = IResupplyRegistry(registry).redemptionHandler();
        uint256 rfee = IRedemptionHandler(rhandler).baseRedemptionFee();
        uint256 floorrate = 1e18 - rfee;

        //take higher of pool price and redemption floor
        return _price > floorrate ? _price : floorrate;
    }

    function decimals() external pure returns (uint8) {
        return DECIMALS;
    }
}
