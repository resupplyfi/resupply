// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IResupplyPair } from "../interfaces/IResupplyPair.sol";
import { IResupplyRegistry } from "../interfaces/IResupplyRegistry.sol";
import { IOracle } from "../interfaces/IOracle.sol";
import { IRewardHandler } from "../interfaces/IRewardHandler.sol";
import { IRewards } from "../interfaces/IRewards.sol";
import { IConvexPoolUtil } from "../interfaces/IConvexPoolUtil.sol";
import { ICurveExchange } from "../interfaces/ICurveExchange.sol";
import { ISwapper } from "../interfaces/ISwapper.sol";
import { ResupplyPairConstants } from "../protocol/pair/ResupplyPairConstants.sol";
import { IERC4626 } from "../interfaces/IERC4626.sol";


/*
This is a utility library which is mainly used for off chain calculations
*/
contract Utilities is ResupplyPairConstants{

    address public constant convexPoolUtil = address(0x5Fba69a794F395184b5760DAf1134028608e5Cd1);

    address public immutable registry;
    uint32 public constant TYPE_UNDEFINED = 0;
    uint32 public constant TYPE_SWAP = 1;
    uint32 public constant TYPE_DEPOSIT = 2;
    uint32 public constant TYPE_WITHDRAW = 3;

    constructor(address _registry){
        registry = _registry;
    }

    function getSwapRouteAmountOut(uint256 _amount, address _swapper, address[] calldata _path) public view returns(uint256 _returnAmount){
        _returnAmount = _amount;
        for(uint256 i=0; i < _path.length-1;){
            (address swappool, int32 tokenInIndex, int32 tokenOutIndex, uint32 swaptype) = ISwapper(_swapper).swapPools(_path[i],_path[i+1]);

            if(swaptype == TYPE_UNDEFINED){
                //assume if i is 0 we want to withdraw
                //assume if i is anything else we want to deposit
                swappool = _path[i];
                if(i==0){
                    swaptype = TYPE_WITHDRAW;
                }else{
                    swaptype = TYPE_DEPOSIT;
                }
            }

            if(swaptype == TYPE_DEPOSIT){
                //if set as a deposit, use 4626 interface
                _returnAmount = IERC4626(swappool).previewDeposit(_returnAmount);
            }else if(swaptype == TYPE_WITHDRAW){
                //if set as a withdraw, use 4626 interface redeem
                _returnAmount = IERC4626(swappool).previewRedeem(_returnAmount);
            }else{
                //curve pool swap, use get_dy
                _returnAmount = ICurveExchange(swappool).get_dy(int128(tokenInIndex), int128(tokenOutIndex), _returnAmount);
            }
            unchecked{ i += 1;}
        }
    }

    //check if given account on given pair is solvent
    function isSolvent(address _pair, address _account) external returns(bool){
        uint256 _maxLTV = IResupplyPair(_pair).maxLTV();

        if (_maxLTV == 0) return true;
        
        IResupplyPair(_pair).previewAddInterest();

        //get borrow shares/amount
        uint256 userBorrowShares = IResupplyPair(_pair).userBorrowShares(_account);
        uint256 borrowerAmount = IResupplyPair(_pair).toBorrowAmount(userBorrowShares, true);

        if (borrowerAmount == 0) return true;
        
        //get collateral
        uint256 collateralAmount = IResupplyPair(_pair).userCollateralBalance(_account);
        if (collateralAmount == 0) return false;

        //get exchange rate
        (address oracle, , ) = IResupplyPair(_pair).exchangeRateInfo();
        address collateralVault = IResupplyPair(_pair).collateral();
        uint256 exchangeRate = IOracle(oracle).getPrices(collateralVault);
        //convert price of collateral as debt is priced in terms of collateral amount (inverse)
        exchangeRate = 1e36 / exchangeRate;

        uint256 _ltv = ((borrowerAmount * exchangeRate * LTV_PRECISION) / EXCHANGE_PRECISION) / collateralAmount;
        return _ltv <= _maxLTV;
    }

    function isSolventAfterLeverage(address _pair, address _account, uint256 _addUnderlying, uint256 _borrowAmount, uint256 _slippage, address _swapper, address[] calldata _path) external returns(bool){
        uint256 _maxLTV = IResupplyPair(_pair).maxLTV();

        if (_maxLTV == 0) return true;
        
        IResupplyPair(_pair).previewAddInterest();

        //get borrow shares/amount
        uint256 userBorrowShares = IResupplyPair(_pair).userBorrowShares(_account);
        uint256 borrowerAmount = IResupplyPair(_pair).toBorrowAmount(userBorrowShares, true);

        //add the new borrow amount
        borrowerAmount += _borrowAmount;
        
        //get collateral
        uint256 collateralAmount = IResupplyPair(_pair).userCollateralBalance(_account);

        //get exchange rate
        (address oracle, , ) = IResupplyPair(_pair).exchangeRateInfo();
        address collateralVault = IResupplyPair(_pair).collateral();
        uint256 exchangeRate = IOracle(oracle).getPrices(collateralVault);
        //convert price of collateral as debt is priced in terms of collateral amount (inverse)
        exchangeRate = 1e36 / exchangeRate;

        //add underlying
        if(_addUnderlying > 0){
            collateralAmount += IERC4626(collateralVault).previewDeposit(_addUnderlying);
        }

        //get exchange rate of the amount borrowed to collateral amount
        uint256 collateralReceived = getSwapRouteAmountOut(_borrowAmount, _swapper, _path);
        //assume a reduciton of the returned amount defined by slippage
        collateralReceived = collateralReceived * _slippage / 1e18;

        //add to collateral amouont
        collateralAmount += collateralReceived;

        uint256 _ltv = ((borrowerAmount * exchangeRate * LTV_PRECISION) / EXCHANGE_PRECISION) / collateralAmount;
        return _ltv <= _maxLTV;
    }


    function apr(uint256 _rate, uint256 _priceOfReward, uint256 _priceOfDeposit) external view returns(uint256 _apr){
        return _rate * 365 days * _priceOfReward / _priceOfDeposit; 
    }

    //get rates for rewards received via collateral deposits
    //note: has an extra 1e18 decimals of precision
    function pairCollateralRewardRates(address _pair) public view returns (address[] memory tokens, uint256[] memory rates) {
        
        uint256 pid = IResupplyPair(_pair).convexPid();
        if(pid == 0){
            return (new address[](0), new uint256[](0));
        }

        //get reward rates on convex pools per collateral token
        (tokens, rates) = IConvexPoolUtil(convexPoolUtil).rewardRates(pid);

        //convert each rate from per collateral token to per debt share
        (,uint128 totalBorrow) = IResupplyPair(_pair).totalBorrow();
        uint256 totalCollateral = IResupplyPair(_pair).totalCollateral();
        if(totalBorrow == 0){
            totalBorrow = 1;
        }
        uint256 cbRatio = totalCollateral * 1e36 / uint256(totalBorrow);

        uint256 rlength = rates.length;
        for(uint256 i = 0; i < rlength; i++){
            //leave an extra 1e18 of precision by not dividing by 1e18 and let UI do the rest
            rates[i] = rates[i] * cbRatio;
        }
    }

    //get emission reward rates per borrow share on a given pair
    //note: has an extra 1e18 decimals of precision
    function getPairRsupRate(address _pair) external view returns(address[] memory tokens, uint256[] memory rates){
        address rewardHandler = IResupplyRegistry(registry).rewardHandler();
        address pairEmissions = IRewardHandler(rewardHandler).pairEmissions();

        //only 1 token and its known what its address is, but returning
        //arrays here to align with the other rate calls
        tokens = new address[](1);
        tokens[0] = IResupplyRegistry(registry).govToken();
        rates = new uint256[](1);

        if(IRewards(pairEmissions).periodFinish() >= block.timestamp){

            uint256 rewardRate = IRewards(pairEmissions).rewardRate();
            uint256 totalsupply = IRewards(pairEmissions).totalSupply();
            uint256 pairWeight = IRewards(pairEmissions).balanceOf(_pair);
            if(totalsupply == 0){
                totalsupply = 1;
            }

            //reward rate for this pair only
            //add an extra 1e18 padding of precision and let UI do the rest
            rewardRate = rewardRate * pairWeight * 1e36 / totalsupply;
            rates[0] = rewardRate;

            (,uint256 pairShares) = IResupplyPair(_pair).totalBorrow();
            if(pairShares > 0){
                rates[0] = rates[0] * 1e18 / pairShares;
            }
        }
    }

    //get emission rewards and protocol revenue share rates per pool share for the insurance pool
    //note: has an extra 1e18 decimals of precision
    function getInsurancePoolRewardRates() external view returns(address[] memory tokens, uint256[] memory rates){
        address rewardHandler = IResupplyRegistry(registry).rewardHandler();
        address insurancePool = IResupplyRegistry(registry).insurancePool();
        address insuranceEmissions = IRewardHandler(rewardHandler).insuranceEmissions();
        address insuranceRevenue = IRewardHandler(rewardHandler).insuranceRevenue();
        uint256 totalSupply = IRewards(insurancePool).totalSupply();

        tokens = new address[](2);
        tokens[0] = IResupplyRegistry(registry).govToken();
        tokens[1] = IResupplyRegistry(registry).token();
        rates = new uint256[](2);

        //gov token
        uint256 rewardRate = IRewards(insuranceEmissions).rewardRate();
        uint256 totalWeight = IRewards(insuranceEmissions).totalSupply();
        uint256 poolWeight = IRewards(insuranceEmissions).balanceOf(insurancePool);
        if(totalWeight == 0){
            totalWeight = 1;
        }
        //weight should be fully on the insurance pool but just in case..
        //add an extra 1e18 padding of precision and let UI do the rest
        rewardRate = rewardRate * poolWeight * 1e36 / totalWeight;

        if(IRewards(insuranceEmissions).periodFinish() >= block.timestamp){
            rates[0] = rewardRate;
            
            if(totalSupply > 0){
                rates[0] = rates[0] * 1e18 / totalSupply;
            }
        }

        //stable token
        rewardRate = IRewards(insuranceRevenue).rewardRate();
        totalWeight = IRewards(insuranceRevenue).totalSupply();
        poolWeight = IRewards(insuranceRevenue).balanceOf(insurancePool);
        if(totalWeight == 0){
            totalWeight = 1;
        }
        //weight should be fully on the insurance pool but just in case..
        //add an extra 1e18 padding of precision and let UI do the rest
        rewardRate = rewardRate * poolWeight * 1e36 / totalWeight;

        if(IRewards(insuranceRevenue).periodFinish() >= block.timestamp){
            rates[1] = rewardRate;
            
            if(totalSupply > 0){
                rates[1] = rates[1] * 1e18 / totalSupply;
            }
        }
    }
}
