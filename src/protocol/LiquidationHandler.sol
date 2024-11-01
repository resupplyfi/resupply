// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { CoreOwnable } from '../dependencies/CoreOwnable.sol';
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "../libraries/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IPairRegistry } from "../interfaces/IPairRegistry.sol";
import { IResupplyPair } from "../interfaces/IResupplyPair.sol";
import { IInsurancePool } from "../interfaces/IInsurancePool.sol";
import { IERC4626 } from "../interfaces/IERC4626.sol";


//Receive collateral from pairs during liquidations and process
//send underlying to insurance pool while burning debt to compensate
contract LiquidationHandler is CoreOwnable{
    using SafeERC20 for IERC20;

    address public immutable registry;
    address public immutable insurancepool;
    mapping(address => uint256) public debtByCollateral;

    event CollateralProccessed(address indexed _collateral, uint256 _collateralAmount, uint256 _debtAmount);

    constructor(address _core, address _registry, address _insurancepool) CoreOwnable(_core){
        registry = _registry;
        insurancepool = _insurancepool;
    }

    //allow protocol to migrate collateral left in this handler if an update is required
    //registry must point to a different handler to ensure this contract is no longer being used
    function migrateCollateral(address _collateral, uint256 _amount, address _to) external onlyOwner{
        require(IPairRegistry(registry).liquidationHandler() != address(this), "handler still used");
        IERC20(_collateral).safeTransfer(_to, _amount);
    }

    function liquidate(
        address _pair,
        address _borrower
    ) external returns (uint256 _collateralForLiquidator){
        _collateralForLiquidator = IResupplyPair(_pair).liquidate(_borrower);
    }

    function processLiquidationDebt(address _collateral, uint256 _collateralAmount, uint256 _debtAmount) external{
        //ensure caller is a registered pair
        require(IPairRegistry(registry).pairsByName(IERC20Metadata(msg.sender).name()) == msg.sender, "!regPair");

        //add to debt needed to burn
        debtByCollateral[_collateral] += _debtAmount;

        //process
        processCollateral(_collateral);
    }

    //withdraw what is possible and send to insurance pool while
    //burning required debt
    function processCollateral(address _collateral) public{
        require(IPairRegistry(registry).liquidationHandler() == address(this), "!liq handler");
        
        //get underlying
        address underlyingAsset = IERC4626(_collateral).asset();

        //sanity check that the collateral is still valued above debt (assuming value of underlying is stable)
        //if not, burn to adjust
        uint256 sharesToAssets = IERC4626(_collateral).convertToAssets(IERC20(_collateral).balanceOf(address(this)));
        if(sharesToAssets < debtByCollateral[_collateral]){
            //get the difference in value of outstanding debt and underlying assets
            sharesToAssets = debtByCollateral[_collateral] - sharesToAssets;
            //burn to balance
            IInsurancePool(insurancepool).burnAssets(sharesToAssets);
        }


        //try to max redeem
        uint256 redeemable = IERC4626(_collateral).maxRedeem(address(this));
        if(redeemable == 0) return;
        try IERC4626(_collateral).redeem(redeemable, address(this), address(this)){}catch{}

        //check what was withdrawn
        uint256 withdrawnAmount = IERC20(underlyingAsset).balanceOf(address(this));
        if(withdrawnAmount == 0) return;

        //debt to burn (clamp to debtByCollateral)
        uint256 toburn = withdrawnAmount > debtByCollateral[_collateral] ? debtByCollateral[_collateral] : withdrawnAmount;
        IInsurancePool(insurancepool).burnAssets(toburn);

        //update remaining debt (toburn should not be greater than debtByCollateral as its adjusted above)
        debtByCollateral[_collateral] -= toburn;

        //send underlying to be distributed
        IERC20(underlyingAsset).safeTransfer(insurancepool, withdrawnAmount);
    }
}