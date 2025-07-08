pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IResupply {
    function collateral() external view returns (address);
    function getAllPairAddresses() external view returns (address[] memory);
}

contract ShareBurner {

    IResupply public constant registry = IResupply(0x10101010E0C3171D894B71B3400668aF311e7D94);
    IERC20 public constant crvusd = IERC20(0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E);
    IERC20 public constant frxusd = IERC20(0xCAcd6fd266aF91b8AeD52aCCc382b4e165586E29);
    uint256 public index;

    function burn() external {
        address[] memory pairs = registry.getAllPairAddresses();
        uint i = index;
        for (; i < pairs.length; i++) {
            IResupply pair = IResupply(pairs[i]);
            IERC4626 collateral = IERC4626(pair.collateral());
            if (collateral.asset() == address(frxusd)) {
                frxusd.approve(address(collateral), type(uint256).max);
                collateral.deposit(1e18, address(this));
            }
            else if (collateral.asset() == address(crvusd)) {
                crvusd.approve(address(collateral), type(uint256).max);
                collateral.deposit(1e18, address(this));
            }
        }
        index = i;
    }
}