// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IProxyFactory } from "../interfaces/IProxyFactory.sol";
import { ICurveLendMinter } from "../interfaces/ICurveLendMinter.sol";



contract CurveLendMinterFactory is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address;

    address public constant CRVUSD = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
    address public constant proxyFactory = 0xf53173a3104bFdC4eD2FA579089B5e6Bf4fc7a2b;
    address public immutable crvusdController;
    
    address public fee_receiver;
    address public implementation;
    mapping(address => address) public markets;

    event SetImplementation (address indexed _implementation);
    event SetFeeReceiver (address indexed _receiver);
    event AddMarket (address indexed _market, address indexed _lender);
    event RemoveMarket (address indexed _market);

    constructor(address _owner, address _crvusdController, address _initialImplementation) Ownable(_owner) {
        crvusdController = _crvusdController;
        implementation = _initialImplementation;
    }

    function setImplementation(address _implementation) external nonReentrant onlyOwner{
        implementation = _implementation;
        emit SetImplementation(_implementation);
    }

    function setFeeReceiver(address _receiver) external nonReentrant onlyOwner{
        fee_receiver = _receiver;
        emit SetFeeReceiver(_receiver);
    }

    //add a market to mapping that allows borrowing funds
    //a market is ambiguous and doesnt technically need to be a CurveLend market
    function addMarket(address _market) external nonReentrant onlyOwner returns(address){
        //clone a new market
        address marketLender = IProxyFactory(proxyFactory).clone(implementation);

        //initialize
        ICurveLendMinter(marketLender).initialize(owner(), address(this), _market);

        //insert market lender into mapping, this will override an existing entry
        //if an entry is overriden, the old lender will not be allowed to borrow more
        //but should still be able to repay
        markets[_market] = marketLender;
        emit AddMarket(_market, marketLender);

        return marketLender;
    }

    function removeMarket(address _market) external nonReentrant onlyOwner{
        //remove any lender reference to the given market
        //that market will not be able to borrow more
        //but should still be able to repay
        markets[_market] = address(0);
        emit RemoveMarket(_market);
    }


    function pull_funds(address _market, uint256 _amount) external nonReentrant{
        //check that msg sender is a valid market lender
        require(msg.sender == markets[_market], "Invalid Access");

        //each market has its limits set locally and the factory trusts it
        IERC20(CRVUSD).safeTransfer(msg.sender, _amount);
    }
}