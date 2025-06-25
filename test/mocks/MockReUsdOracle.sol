pragma solidity 0.8.28;

contract MockReUsdOracle {
    uint256 public price;

    constructor() {
        price = 1e18;
    }

    function setPrice(uint256 _price) public {
        price = _price;
    }
}