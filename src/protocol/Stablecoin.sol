// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { CoreOwnable } from '../dependencies/CoreOwnable.sol';


contract Stablecoin is ERC20Permit, CoreOwnable {

    mapping(address => bool) public operators;
    event SetOperator(address indexed _op, bool _valid);

    constructor(address _core)
        ERC20("Resupply USD", "reUSD")
        ERC20Permit("Resupply USD")
        CoreOwnable(_core)
    {
        //premint a small amount to deployer so that it can be used in the full deployment sequence
        //ex. insurance pool needs a small seed
        _mint(msg.sender, 1e18);
    }

   function setOperator(address _operator, bool _valid) external onlyOwner{
        operators[_operator] = _valid;
        emit SetOperator(_operator, _valid);
    }

    function mint(address _to, uint256 _amount) external {
        require(operators[msg.sender] || msg.sender == owner(), "!authorized");
        
        _mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) external {
        // Allow msg.sender to burn from themselves
        if (msg.sender != _from) {
            _spendAllowance(_from, msg.sender, _amount);
        }
        _burn(_from, _amount);
    }
}