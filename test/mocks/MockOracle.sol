// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

// basic oracle that assumes the underlying value and returns erc4626 share to assets conversion
contract MockOracle {

    uint8 internal constant DECIMALS = 18;
    string public name;
    uint256 public price;

    constructor(string memory _name, uint256 _price) {
        name = _name;
        price = _price;
    }

    function getPrices(address _vault) external view returns (uint256 _price) {
        return price;
    }

    function setPrice(uint256 _price) external {
        price = _price;
    }

    function decimals() external pure returns (uint8) {
        return DECIMALS;
    }
}
