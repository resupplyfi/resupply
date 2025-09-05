// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC4626 } from "../interfaces/IERC4626.sol";
import { ICurveLendMinterFactory } from "../interfaces/ICurveLendMinterFactory.sol";



contract CurveLendMinter is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address;

    address public constant CRVUSD = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;

    address public market;
    address public factory;
    uint256 public mintLimit;
    uint256 public mintedAmount;

    event NewLimit (uint256 limit);
    event MintedAmountReduced (uint256 amount);

    constructor(){}

    modifier onlyOwner() {
        require(msg.sender == admin(), "!admin");
        _;
    }

    function admin() public returns(address){
        return ICurveLendMinterFactory(factory).admin();
    }

    function initialize(address _factory, address _market) external nonReentrant{
        require(market == address(0),"!init");
        market = _market;
        factory = _factory;
        IERC20(CRVUSD).forceApprove(_market, type(uint256).max);
    }


    //set a new mint limit for the market
    function setMintLimit(uint256 _newLimit) external nonReentrant onlyOwner{
        //set the new mint limit
        mintLimit = _newLimit;
        emit NewLimit(_newLimit);

        //check if growth
        if(mintedAmount < _newLimit){
            //get difference of mintedAmount and newLimit
            uint256 difference = _newLimit - mintedAmount;

            //pull needed funds from factory (will fail if factory does not have adaquate funds)
            ICurveLendMinterFactory(factory).borrow(market, difference);
            mintedAmount += difference;

            //deposit all crvusd on this contract into the market 
            IERC4626(market).deposit(IERC20(CRVUSD).balanceOf(address(this)), address(this));
        }
    }

    //reduce mintedAmount to mintLimit
    //this is openly callable as the market might not be completely liquid at any given time
    //owner just needs to adjust the target
    function reduceAmount(uint256 _amount) external nonReentrant{
        require(mintedAmount > mintLimit, "can not reduce");

        //withdraw funds (can over withdraw as we will redeposit left overs)
        IERC4626(market).withdraw(_amount, address(this), address(this));
        
        //get balance of crvusd on contract
        uint256 balance = IERC20(CRVUSD).balanceOf(address(this));

        //clamp to mint limit
        uint256 returnAmount = mintedAmount - mintLimit;
        returnAmount = balance > returnAmount ? returnAmount : balance;
        mintedAmount -= returnAmount;

        //transfer funds back to factory
        IERC20(CRVUSD).safeTransfer(factory, returnAmount);
        emit MintedAmountReduced(returnAmount);

        //redeposit anything left over
        if(balance > returnAmount){
            IERC4626(market).deposit(balance - returnAmount, address(this));
        }
    }

    //take profit
    //note this could revert if profit is more than the available liquidity in the market
    //we will keep it simple and just wait for availability
    function takeProfit() external nonReentrant{
        //calculate difference of current total balance and minted amount to get profit
        uint256 currentAssets = IERC4626(market).convertToAssets(IERC20(market).balanceOf(address(this)));

        //if current assets is greated than minted amount, can take profit
        if(currentAssets > mintedAmount){
            //get difference as profit
            currentAssets -= mintedAmount;

            //withdraw to factory fee receiver
            IERC4626(market).withdraw(currentAssets, ICurveLendMinterFactory(factory).fee_receiver(), address(this));
        }
    }
}