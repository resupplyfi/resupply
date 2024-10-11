// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import { IERC4626 } from "../interfaces/IERC4626.sol";

// basic oracle that assumes the underlying value and returns erc4626 share to assets conversion
contract BasicVaultOracle {
   
    // Config Data
    uint8 internal constant DECIMALS = 18;
    string public name;
    uint256 public oracleType = 1;

    constructor(
        string memory _name
    ) {
        name = _name;
    }

    /// @notice The ```getPrices``` function return shares to assets of given vault
    /// @return _isBadData is true when value is uncertain
    /// @return _priceLow is share to asset ratio
    /// @return _priceHigh is share to asset ratio
    function getPrices(address _vault) external view returns (bool _isBadData, uint256 _priceLow, uint256 _priceHigh) {
        _priceLow = IERC4626(_vault).convertToAssets(1e18);
        _priceHigh = _priceLow;
    }

    function decimals() external pure returns (uint8) {
        return DECIMALS;
    }
}
