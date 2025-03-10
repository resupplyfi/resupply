// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { OFT } from "@layerzerolabs/oft-evm/contracts/OFT.sol";

contract Stablecoin is OFT {

    mapping(address => bool) public operators;
    event SetOperator(address indexed _op, bool _valid);

    constructor(address _core, address _endpoint)
        OFT("Resupply USD", "reUSD", _endpoint, _core)
        Ownable(_core)
    {
        //premint a small amount to deployer so that it can be used in the full deployment sequence
        //ex. insurance pool needs a small seed
        _mint(msg.sender, 1e18);
    }

    function core() external view returns(address) {
        return owner();
    }

    function _transferOwnership(address newOwner) internal override {
        if(owner() == address(0)){
            super._transferOwnership(newOwner);
        }else{
            revert OwnableInvalidOwner(newOwner);
        }
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