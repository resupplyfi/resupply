// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "../libraries/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IPairRegistry } from "../interfaces/IPairRegistry.sol";
import { IFraxlendPair } from "../interfaces/IFraxlendPair.sol";


//Receive collateral from pairs during liquidations and process
contract LiquidationHandler is Ownable2Step{
    using SafeERC20 for IERC20;

    address public immutable registry;
    address public immutable insurancepool;

    // address public receiverPlatform;
    // address public receiverInsurance;
    address public operator;

    event CollateralProccessed(address indexed _collateral, uint256 _collateralAmount, uint256 _debtAmount);

    constructor(address _owner, address _registry, address _insurancepool) Ownable2Step(){
        registry = _registry;
        insurancepool = _insurancepool;
        _transferOwnership(_owner);
    }

    modifier onlyOperator() {
        require(operator == msg.sender, "!operator");
        _;
    }

    event SetOperator(address oldAddress, address newAddress);

    function setOperator(address _newAddress) external onlyOwner{
        emit SetOperator(operator, _newAddress);
        operator = _newAddress;
    }

    function liquidate(
        address _pair,
        address _borrower
    ) external returns (uint256 _collateralForLiquidator){
        return IFraxlendPair(_pair).liquidate(_borrower);
    }

    function processCollateral(address _collateral, uint256 _collateralAmount, uint256 _debtAmount) external{
        //ensure caller is a registered pair
        require(IPairRegistry(registry).deployedPairsByName(IERC20Metadata(msg.sender).name()) == msg.sender, "!regPair");

        /*TODO
            withdraw max possible from collateral
            send whats possible
            handle non withdrawable
            burn debt off insurance pool
            handle insurance pool too small
        */
        
    }
}