// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IERC4626 } from "../../src/interfaces/IERC4626.sol";

/// @title Mock Oracle Contract
/// @notice A mock oracle contract for testing purposes that can return either a fixed price or actual ERC4626 vault share price
/// @dev Implements basic oracle functionality with ability to override price for testing scenarios
contract MockOracle {

    uint8 internal constant DECIMALS = 18;
    string public name;
    uint256 public price;

    constructor(string memory _name, uint256 _price) {
        name = _name;
        price = _price;
    }

    function getPrices(address _vault) external view returns (uint256 _price) {
        if (price == 0) {
            return _getActualPrice(_vault);
        }
        return price;
    }

    function _getActualPrice(address _vault) internal view returns (uint256) {
        return IERC4626(_vault).convertToAssets(1e18);
    }

    function setPrice(uint256 _price) external {
        price = _price;
    }

    function decimals() external pure returns (uint8) {
        return DECIMALS;
    }
}
