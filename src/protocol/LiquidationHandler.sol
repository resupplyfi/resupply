// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { CoreOwnable } from '../dependencies/CoreOwnable.sol';
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "../libraries/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IResupplyRegistry } from "../interfaces/IResupplyRegistry.sol";
import { IResupplyPair } from "../interfaces/IResupplyPair.sol";
import { IInsurancePool } from "../interfaces/IInsurancePool.sol";
import { IRewards } from "../interfaces/IRewards.sol";
import { IERC4626 } from "../interfaces/IERC4626.sol";


//Receive collateral from pairs during liquidations and process
//send underlying to insurance pool while burning debt to compensate
contract LiquidationHandler is CoreOwnable{
    using SafeERC20 for IERC20;

    address public immutable registry;
    address public immutable insurancePool;
    mapping(address => uint256) public debtByCollateral;

    event CollateralProccessed(address indexed _collateral, uint256 _debtBurned, uint256 _profit);
    event CollateralDistributedAndDebtCleared(address indexed _collateral, uint256 _collateralAmount, uint256 _debtAmount);
    event CollateralMigrated(address indexed _collateral, uint256 _collateralAmount, address _newHandler);

    constructor(address _core, address _registry, address _insurancePool) CoreOwnable(_core){
        registry = _registry;
        insurancePool = _insurancePool;
    }

    //allow protocol to migrate collateral left in this handler if an update is required
    //registry must point to a different handler to ensure this contract is no longer being used
    function migrateCollateral(address _collateral) external returns(uint256 debtCanceled){
        address currentHandler = IResupplyRegistry(registry).liquidationHandler();
        require(currentHandler != address(this), "handler still used");
        require(currentHandler == msg.sender, "!liq handler");

        //return how much debt was cleared so new handler can process
        debtCanceled = debtByCollateral[_collateral];

        //clear debt
        debtByCollateral[_collateral] = 0;

        uint256 collateralAmount = IERC20(_collateral).balanceOf(address(this));
        IERC20(_collateral).safeTransfer(currentHandler, collateralAmount);

        emit CollateralMigrated(_collateral, collateralAmount, currentHandler);
    }

    //if there is bad debt in the system where the collateral on this handler is
    //worth less than the amount of debt owed then the protocol should be able to choose to
    //immediately clear debt and distribute the "bad" collateral to insurance pool holders
    function distributeCollateralAndClearDebt(address _collateral) external onlyOwner{
        require(IResupplyRegistry(registry).liquidationHandler() == address(this), "!liq handler");

        //first need to make sure collateral is a valid reward before sending or else it wont get distributed
        //get reward slot
        uint256 slot = IRewards(insurancePool).rewardMap(_collateral);
        require(slot > 0, "!non registered reward");
        //check if invalidated (slot minus one to adjust for slot starting from 1)
        (address reward_token,,) = IRewards(insurancePool).rewards(slot-1);
        require(reward_token == _collateral,"invalidated reward");
        //collateral is a valid reward token and can be sent

        //first try redeeming as much of the underlying as possible
        processCollateral(_collateral);

        //get balance
        uint256 collateralBalance = IERC20(_collateral).balanceOf(address(this));
        
        uint256 maxBurnable = IInsurancePool(insurancePool).maxBurnableAssets();

        //get how much debt this collateral has
        uint256 collateralDebt = debtByCollateral[_collateral];

        //check that it is indeed burnable..
        if(collateralDebt <= maxBurnable){
            //burn debt
            IInsurancePool(insurancePool).burnAssets(collateralDebt);
            //clear debt
            debtByCollateral[_collateral] = 0;

            if(collateralBalance > 0){
                //send all collateral (and thus distribute)
                IERC20(_collateral).safeTransfer(insurancePool, collateralBalance);
            }

            emit CollateralDistributedAndDebtCleared(_collateral, collateralBalance, debtByCollateral[_collateral]);
        }
    }

    function liquidate(
        address _pair,
        address _borrower
    ) external returns (uint256 _collateralForLiquidator){
        _collateralForLiquidator = IResupplyPair(_pair).liquidate(_borrower);
    }

    function processLiquidationDebt(address _collateral, uint256 _collateralAmount, uint256 _debtAmount) external{
        //ensure caller is authorized
        require(IResupplyRegistry(registry).pairsByName(IERC20Metadata(msg.sender).name()) == msg.sender ||
            IResupplyRegistry(registry).l2manager() == msg.sender, "!regPair");

        //add to debt needed to burn
        debtByCollateral[_collateral] += _debtAmount;

        //process
        processCollateral(_collateral);
    }

    //withdraw what is possible and send to insurance pool while
    //burning required debt
    function processCollateral(address _collateral) public{
        require(IResupplyRegistry(registry).liquidationHandler() == address(this), "!liq handler");
        
        //get max withdraw
        uint256 withdrawable = IERC4626(_collateral).maxWithdraw(address(this));
        //get how much debt this collateral has
        uint256 collateralDebt = debtByCollateral[_collateral];
        //debt to burn (clamp to debtByCollateral)
        uint256 toBurn = withdrawable > collateralDebt ? collateralDebt : withdrawable;
        //get max burnable
        uint256 maxBurnable = IInsurancePool(insurancePool).maxBurnableAssets();

        if(toBurn <= maxBurnable){
            uint256 withdrawnAmount;
            try IERC4626(_collateral).redeem(
                IERC4626(_collateral).maxRedeem(address(this)), 
                insurancePool, 
                address(this)
            ) returns (uint256 _withdrawnAmount){
                withdrawnAmount = _withdrawnAmount;
            } catch{}

            if(withdrawnAmount == 0) return;

            //its possible redeemed amount could be slightly different than the above maxWithdraw so recompute toburn
            toBurn = withdrawnAmount > collateralDebt ? collateralDebt : withdrawnAmount;
        
            //burn
            IInsurancePool(insurancePool).burnAssets(toBurn);

            //update remaining debt (toBurn should not be greater than debtByCollateral as its adjusted above)
            debtByCollateral[_collateral] -= toBurn;

            emit CollateralProccessed(_collateral, toBurn, withdrawnAmount - toBurn);
        }
    }
}