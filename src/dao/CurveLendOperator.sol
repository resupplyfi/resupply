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
    address public constant BURN_ADDRESS = address(0xdead);
    uint256 public constant REQUIRED_BURN_AMOUNT = 1000e18; //1000:1 starting share to asset ratio

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
    function initialize(address _factory, address _market, uint256 _initialMintLimit) external nonReentrant{
        require(market == address(0),"!init");
        market = _market;
        factory = _factory;


        //while the DAO should ensure that any market an operator is properly setup and in working condition,
        //one simple integrity check we can do here is to check if shares have been burnt
        require(IERC20(_market).balanceOf(BURN_ADDRESS) >= REQUIRED_BURN_AMOUNT, "Must burn first");


        //approve all crvusd transfers to the underlying market
        IERC20(CRVUSD).forceApprove(_market, type(uint256).max);

        //set initial limit
        _setMintLimit(_initialMintLimit);
    }


    /// @notice The ```setMintLimit``` sets a new borrow limit for the operator
    /// @param _newLimit the new limit to use
    function setMintLimit(uint256 _newLimit) external nonReentrant onlyOwner{
        _setMintLimit(_newLimit);
    }

    function _setMintLimit(uint256 _newLimit) internal{
        //set the new mint limit
        mintLimit = _newLimit;
        emit NewLimit(_newLimit);

        //check if growth
        if(mintedAmount < _newLimit){
            //get difference of mintedAmount and newLimit
            uint256 difference = _newLimit - mintedAmount;

            //pull needed funds from factory (will fail if factory does not have adequate funds)
            ICurveLendMinterFactory(factory).borrow(market, difference);
            mintedAmount += difference;

            //deposit all crvusd on this contract into the market 
            IERC4626(market).deposit(IERC20(CRVUSD).balanceOf(address(this)), address(this));
        }
    }

    /// @notice The ```reduceAmount``` reduce supplied token amounts on market and return to factory
    /// @param _amount amount to reduce
    /// @dev openly callable as market may not always be liquid enough to remove entire balance
    /// @dev reduceAmount will clamp to value so that minted amount does not go below mint limit
    /// @return final amount reduced
    function reduceAmount(uint256 _amount) external nonReentrant returns(uint256){
        //only reduce when needed
        require(mintedAmount > mintLimit, "can not reduce");

        uint256 maxAmount = mintedAmount - mintLimit;
        _amount = _amount > maxAmount ? maxAmount : _amount;

        //withdraw funds back to factory
        IERC4626(market).withdraw(_amount, factory, address(this));
        
        //updated mintedAmount
        mintedAmount -= _amount;
        emit MintedAmountReduced(_amount);

        return _amount;
    }

    /// @notice The ```profit``` function returns how much assets may be claimed as profit
    /// @return the amount of assets that can be claimed
    function profit() public view returns(uint256){
        //get current asset total
        uint256 currentAssets = IERC4626(market).convertToAssets(IERC20(market).balanceOf(address(this)));

        //if current assets is greater than minted amount, can take profit
        return currentAssets > mintedAmount ? currentAssets - mintedAmount : 0;
    }

    /// @notice The ```withdraw_profit``` function withdraws any profit and sends to factory's fee receiver
    /// @dev note this could revert if profit is more than the available liquidity in the market. must wait for availability
    /// @dev naming convention to align with other Curve contracts
    /// @return _profit amount withdrawn
    function withdraw_profit() external nonReentrant returns(uint256 _profit){
        //get profit
        _profit = profit();

        //if non zero, withdraw
        if(_profit > 0){
            //withdraw to factory fee receiver
            IERC4626(market).withdraw(_profit, ICurveLendMinterFactory(factory).fee_receiver(), address(this));
            emit Profit(_profit);
        }
    }
}