// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ICurveOracle } from "../interfaces/ICurveOracle.sol";
import { IChainlinkOracle } from "../interfaces/IChainlinkOracle.sol";


contract UnderlyingOracle {
   
    address public constant crvusd = address(0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E);
    address public constant crvusd_oracle = address(0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E);
    address public constant frxusd = address(0xCAcd6fd266aF91b8AeD52aCCc382b4e165586E29);
    //note this oracle is chain link for original FRAX which should coincide with frxUSD price
    //could be updated later on as more FRAX is moved to frxUSD
    address public constant frxusd_oracle = address(0xB9E1E3A9feFf48998E45Fa90847ed4D467E8BcfD);

    string public name;
    uint256 public constant oracleType = 2;
    uint8 internal constant DECIMALS = 18;

    constructor(
        string memory _name
    ) {
        name = _name;
    }

    /// @notice The ```getPrices``` function return shares to assets of given vault
    /// @return _price is share to asset ratio
    function getPrices(address _token) external view returns (uint256 _price) {
        if(_token == crvusd){
            _price = ICurveOracle(crvusd_oracle).price_oracle();
        }else if(_token == frxusd){
            _price = uint256(IChainlinkOracle(frxusd_oracle).latestAnswer()) * 1e10;
        }
    }

    function decimals() external pure returns (uint8) {
        return DECIMALS;
    }
}
