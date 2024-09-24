// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interfaces/IProxyFactory.sol";

//Factory to create wrapped staking positions
contract PairFactory{
   
    address public immutable proxyFactory;

    address public owner;
    address public pendingOwner;

    address public pairImplementation;

    event SetPendingOwner(address indexed _address);
    event OwnerChanged(address indexed _address);
    event ImplementationChanged(address _implementation);
    event PairCreated(address _pair);

    constructor(address _owner, address _proxyFactory){
        owner = _owner;
        proxyFactory = _proxyFactory;
        emit OwnerChanged(_owner);
    }

    modifier onlyOwner() {
        require(owner == msg.sender, "!owner");
        _;
    }

    //set next owner
    function setPendingOwner(address _po) external onlyOwner{
        pendingOwner = _po;
        emit SetPendingOwner(_po);
    }

    //claim ownership
    function acceptPendingOwner() external {
        require(msg.sender == pendingOwner, "!p_owner");

        owner = pendingOwner;
        pendingOwner = address(0);
        emit OwnerChanged(owner);
    }

    function setImplementation(address _imp) external onlyOwner{
        pairImplementation = _imp;
        emit ImplementationChanged(_imp);
    }

    function CreateWrapper() external onlyOwner returns (address) {
        //create
        address pair = IProxyFactory(proxyFactory).clone(pairImplementation);
        emit PairCreated(pair);

        //init
        //todo
        
        return pair;
    }
}