// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IProxyFactory } from "../interfaces/IProxyFactory.sol";
import { ICurveLendOperator } from "../interfaces/ICurveLendOperator.sol";


/**
 * @title CurveLendMinterFactory
 * @dev This contract is a factory that creates "market operators" which handle funds in the given underlying lending market.
 * Funds for lending are supplied/minted to this factory and the operators can then borrow/repay based on their individual settings.
 */
contract CurveLendMinterFactory is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address;

    address public constant CRVUSD = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
    address public constant proxyFactory = 0x66807B5598A848602734B82E432dD88DBE13fC8f;
    address public immutable crvusdController;
    
    address public fee_receiver;
    address public implementation;
    mapping(address => address) public markets;

    event SetImplementation (address indexed _implementation);
    event SetFeeReceiver (address indexed _receiver);
    event AddMarket (address indexed _market, address indexed _lender);
    event RemoveMarket (address indexed _market);
    event Borrow (address indexed _market, uint256 _amount);

    /// @notice The ```constructor``` function is called at deployment
    /// @param _owner the owner of this factory
    /// @param _crvusdController the crvUSD controller
    /// @param _feeReceiver initial fee receiver to send profits
    /// @param _initialImplementation initial implementation of market operators
    constructor(address _owner, address _crvusdController, address _feeReceiver, address _initialImplementation) Ownable(_owner) {
        crvusdController = _crvusdController;
        implementation = _initialImplementation;
        fee_receiver = _feeReceiver;
        IERC20(CRVUSD).forceApprove(_crvusdController, type(uint256).max);
    }

    /// @notice The ```admin``` function returns admin role
    /// @return The address of owner/admin
    /// @dev admin() is same as owner(), just matches naming convention used on other Curve contracts
    function admin() external view returns(address){
        return owner();
    }

    /// @notice The ```setImplementation``` function sets implementation address for future markets
    /// @param _implementation the address to use as market implementation
    function setImplementation(address _implementation) external nonReentrant onlyOwner{
        implementation = _implementation;
        emit SetImplementation(_implementation);
    }

    /// @notice The ```setFeeReceiver``` function sets address to forward profits to
    /// @param _receiver the receiving address
    function setFeeReceiver(address _receiver) external nonReentrant onlyOwner{
        fee_receiver = _receiver;
        emit SetFeeReceiver(_receiver);
    }

    /// @notice The ```addMarketOperator``` function creates a new operator which can borrow funds to use on the given market
    /// @param _market the underlying market to use by the cloned implementation
    /// @return the address of the market operator
    /// @dev a market is ambiguous and doesnt technically need to be a CurveLend market
    function addMarketOperator(address _market, uint256 _initialMintLimit) external nonReentrant onlyOwner returns(address){
        require(_market != address(0), "invalid market address");

        //clone a new operator
        address marketOperator = IProxyFactory(proxyFactory).clone(implementation);

        //insert market operator into mapping, this will override an existing entry
        //if an entry is overriden, the old operator will not be allowed to borrow more
        //but should still be able to repay
        markets[_market] = marketOperator;
        emit AddMarket(_market, marketOperator);

        //initialize
        ICurveLendOperator(marketOperator).initialize(address(this), _market, _initialMintLimit);

        return marketOperator;
    }

    /// @notice The ```removeMarketOperator``` function removes the operator for the given market
    /// @param _market the underlying market to used by the operator
    /// @dev removing mapping will stop operators from borrowing additional funds
    /// @dev once a market is removed it can not be readded. addMarketOperator always clones a new contract
    function removeMarketOperator(address _market) external nonReentrant onlyOwner{
        //remove any operator reference to the given market
        markets[_market] = address(0);
        emit RemoveMarket(_market);
    }


    /// @notice The ```borrow``` function allows operators to borrow funds
    /// @param _market the underlying market to used by the operator
    /// @param _amount the amount the operator is requesting to borrow
    /// @dev can only borrow whats on this contract, anything over will revert.
    /// @dev operators are trusted with amounts
    function borrow(address _market, uint256 _amount) external{
        //check that msg sender is a valid market operator
        require(msg.sender == markets[_market], "Invalid Access");

        //each market has its limits set locally and the factory trusts it
        IERC20(CRVUSD).safeTransfer(msg.sender, _amount);
        emit Borrow(_market, _amount);
    }
}