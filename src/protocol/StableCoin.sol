// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { CoreOwnable } from '../dependencies/CoreOwnable.sol';


contract StableCoin is ERC20, CoreOwnable {

    mapping(address => bool) public operators;
    event SetOperator(address indexed _op, bool _valid);

    constructor(address _core)
        ERC20(
            "StableCoin",
            "usdXYZ"
        )
        CoreOwnable(_core)
    {
    }

   function setOperator(address _operator, bool _valid) external onlyOwner{
        operators[_operator] = _valid;
        emit SetOperator(_operator, _valid);
    }

    function mint(address _to, uint256 _amount) external {
        require(operators[msg.sender], "!authorized");
        
        _mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) external {
        //allow msg sender to burn from themselves
        if(msg.sender != _from){
            require(operators[msg.sender], "!authorized");
        }
        _burn(_from, _amount);
    }

}