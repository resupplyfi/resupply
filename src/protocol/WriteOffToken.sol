// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/*
A token-like contract to track write offs via erc20 interfaces to be used
in reward distribution logic

interfaces needed:
- balanceOf
- transfer
- mint

*/
contract WriteOffToken {

    address public immutable owner;
    uint256 public totalSupply;

    constructor(address _owner)
    {
        owner = _owner;
    }

    function mint(uint256 _amount) external{
        if(msg.sender == owner){
            totalSupply += _amount;
        }
    }

    function transfer(address to, uint256 amount) external returns (bool){
        //do nothing
    }

    function balanceOf(address) external view returns (uint256){
        //just return total supply
        return totalSupply;
    }
}