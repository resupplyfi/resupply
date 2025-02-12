// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IERC4626 } from "../interfaces/IERC4626.sol";

// basic oracle that assumes the underlying value and returns erc4626 share to assets conversion
contract BasicVaultOracle {
   
    // Config Data
    uint8 internal constant DECIMALS = 18;
    string public name;
    uint256 public constant oracleType = 1;

    constructor(
        string memory _name
    ) {
        name = _name;
    }

    /// @notice The ```getPrices``` function return shares to assets of given vault
    /// @return _price is share to asset ratio
    function getPrices(address _vault) external view returns (uint256 _price) {
        _price = IERC4626(_vault).convertToAssets(1e18);
    }

    function decimals() external pure returns (uint8) {
        return DECIMALS;
    }
}
