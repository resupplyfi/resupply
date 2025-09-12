// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC4626 } from "../interfaces/IERC4626.sol";
import { ICurveLendMinterFactory } from "../interfaces/ICurveLendMinterFactory.sol";


/**
 * @title CurveLendOperator
 * @dev This contract handles depositing, withdrawing, and taking profit from lending positions
 */
contract CurveLendOperator is ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public constant CRVUSD = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;

    address public market;
    address public factory;
    uint256 public mintLimit;
    uint256 public mintedAmount;

    event NewLimit (uint256 limit);
    event MintedAmountReduced (uint256 amount);
    event Profit (uint256 amount);

    /// @notice The ```constructor``` function is called at deployment
    constructor(){}

    /// @notice the ```onlyOwner``` modifier sets functions as only callable from admin address
    modifier onlyOwner() {
        require(msg.sender == admin(), "!admin");
        _;
    }

    /// @notice The ```admin``` function returns admin role
    /// @return The address of owner/admin
    function admin() public view returns(address){
        return ICurveLendMinterFactory(factory).admin();
    }

    /// @notice The ```initialize``` function initializes the contract
    /// @param _factory the address of the operator factory
    /// @param _market the address of the underlying market to interact with
    function initialize(address _factory, address _market) external nonReentrant{
        require(market == address(0),"!init");
        market = _market;
        factory = _factory;
        //approve all crvusd transfers to the underlying market
        IERC20(CRVUSD).forceApprove(_market, type(uint256).max);
    }


    /// @notice The ```setMintLimit``` sets a new borrow limit for the operator
    /// @param _newLimit the new limit to use
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

    /// @notice The ```reduceAmount``` reduce supplied token amounts on market and return to factory
    /// @param _amount amount to reduce
    /// @dev openly callable as market may not always be liquid enough to remove entire balance
    function reduceAmount(uint256 _amount) external nonReentrant{
        //only reduce when needed
        require(mintedAmount > mintLimit, "can not reduce");

        uint256 maxAmount = mintedAmount - mintLimit;
        _amount = _amount > maxAmount ? maxAmount : _amount;

        //withdraw funds back to factory
        IERC4626(market).withdraw(_amount, factory, address(this));
        
        //updated mintedAmount
        mintedAmount -= _amount;
        emit MintedAmountReduced(_amount);
    }

    /// @notice The ```withdraw_profit``` function withdraws any profit and sends to factory's fee receiver
    /// @dev note this could revert if profit is more than the available liquidity in the market. must wait for availability
    /// @dev naming convention to align with other Curve contracts
    function withdraw_profit() external nonReentrant{
        //get current asset total
        uint256 currentAssets = IERC4626(market).previewRedeem(IERC20(market).balanceOf(address(this)));

        //if current assets is greater than minted amount, can take profit
        if(currentAssets > mintedAmount){
            //get difference as profit
            currentAssets -= mintedAmount;

            //withdraw to factory fee receiver
            IERC4626(market).withdraw(currentAssets, ICurveLendMinterFactory(factory).fee_receiver(), address(this));
            emit Profit(currentAssets);
        }
    }
}