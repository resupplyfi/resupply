pragma solidity 0.8.30;

contract MockReUsdOracle {
    uint256 public price;

    constructor() {
        price = 1e18;
    }

    function setPrice(uint256 _price) public {
        price = _price;
    }

    function priceAsCrvusd() external view returns (uint256) {
        return price;
    }

    function priceAsFrxusd() external view returns (uint256) {
        return price;
    }
}