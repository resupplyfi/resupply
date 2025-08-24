// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol } from "src/Constants.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IRateCalculator } from "src/interfaces/IRateCalculator.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IOracle } from "src/interfaces/IOracle.sol";
import { IRewardHandler } from "src/interfaces/IRewardHandler.sol";
import { IRewards } from "src/interfaces/IRewards.sol";
import { IConvexPoolUtil } from "src/interfaces/convex/IConvexPoolUtil.sol";
import { ICurveExchange } from "src/interfaces/curve/ICurveExchange.sol";
import { ICurveLend } from "src/interfaces/curve/ICurveLend.sol";
import { IFraxLend } from "../interfaces/frax/IFraxLend.sol";
import { ISwapper } from "src/interfaces/ISwapper.sol";
import { ResupplyPairConstants } from "src/protocol/pair/ResupplyPairConstants.sol";
import { IERC4626 } from "src/interfaces/IERC4626.sol";
import { IStakedFrax } from "src/interfaces/frax/IStakedFrax.sol";
import { IPriceWatcher } from "src/interfaces/IPriceWatcher.sol";
import { IInterestRateCalculatorV2 } from "src/interfaces/IInterestRateCalculatorV2.sol";

/*
This is a utility library which is mainly used for off chain calculations
*/
contract Utilities is ResupplyPairConstants{
    address public constant INTEREST_RATE_CALCULATORV1 = address(0x77777777729C405efB6Ac823493e6111F0070D67);
    address public constant convexPoolUtil = address(0x5Fba69a794F395184b5760DAf1134028608e5Cd1);
    address public constant sfrxusd = address(0xcf62F905562626CfcDD2261162a51fd02Fc9c5b6);
    address public constant sreusd = address(0x557AB1e003951A73c12D16F0fEA8490E39C33C35);

    address public immutable registry;
    uint32 public constant TYPE_UNDEFINED = 0;
    uint32 public constant TYPE_SWAP = 1;
    uint32 public constant TYPE_DEPOSIT = 2;
    uint32 public constant TYPE_WITHDRAW = 3;

    constructor(address _registry){
        registry = _registry;
    }

    function sfrxusdRates() public view returns(uint256 ratePerSecond){
        return savingsRate(sfrxusd);
    }

    function sreusdRates() public view returns(uint256 ratePerSecond){
        return savingsRate(sreusd);
    }

    function savingsRate(address _vault) public view returns(uint256 ratePerSecond){
        IStakedFrax.RewardsCycleData memory rdata = IStakedFrax(_vault).rewardsCycleData();
        uint256 totalAssets = IStakedFrax(_vault).storedTotalAssets();
        if(totalAssets == 0){
            totalAssets = 1;
        }
        uint256 maxDistro = IStakedFrax(_vault).maxDistributionPerSecondPerAsset();
        ratePerSecond = rdata.rewardCycleAmount / (rdata.cycleEnd - rdata.lastSync);
        ratePerSecond = ratePerSecond * 1e18 / totalAssets;
        ratePerSecond = ratePerSecond > maxDistro ? maxDistro : ratePerSecond;
    }

    function getUnderlyingSupplyRate(address _pair) public view returns(uint256 _rate){
        address collateral = IResupplyPair(_pair).collateral();
        (bool success, ) = collateral.staticcall(abi.encodeWithSelector(bytes4(keccak256("collateral_token()"))));
        if(success){
            //curvelend
            _rate = ICurveLend(collateral).lend_apr() / (365 * 86400);
        }else{
            //fraxlend
            (,,,IFraxLend.CurrentRateInfo memory rateInfo, IFraxLend.VaultAccount memory _totalAsset, IFraxLend.VaultAccount memory _totalBorrow) 
                        = IFraxLend(collateral).previewAddInterest();
            
            uint256 fraxlendRate = rateInfo.ratePerSec * (1e5 - rateInfo.feeToProtocolRate) / 1e5;
            if(_totalAsset.amount > 0){
                _rate = fraxlendRate * _totalBorrow.amount / _totalAsset.amount;
            }
        }
    }

    function getPairInterestRate(address _pair) external view returns(uint256 _ratePerSecond){
        IInterestRateCalculatorV2 calculator = IInterestRateCalculatorV2(IResupplyPair(_pair).rateCalculator());
        uint256 underlyingRate = getUnderlyingSupplyRate(_pair);
        uint256 minimumRate;
        uint256 rateRatio;
        bool isV1 = address(calculator) == INTEREST_RATE_CALCULATORV1;
        // Handle case where dummy calculator is used
        try calculator.minimumRate() returns (uint256 rate) {minimumRate = rate;}
        catch {return 0;}
        
        // V1 calculator
        if(isV1){
            //v1 is constant 50%
            rateRatio = 0.5e18;
            underlyingRate = underlyingRate * rateRatio / 1e18;
            uint256 riskFreeRate = sfrxusdRates() * rateRatio / 1e18;
            _ratePerSecond = minimumRate > riskFreeRate ? minimumRate : riskFreeRate;
            _ratePerSecond = underlyingRate > riskFreeRate ? underlyingRate : riskFreeRate;
        }else{
            //for v2 (and any future versions) use a combination of base+additional
            //with a price weight applied
            uint256 rateRatioBase = calculator.rateRatioBase();
            uint256 rateRatioAdditional = calculator.rateRatioAdditional();
            address priceWatcher = IResupplyRegistry(registry).getAddress("PRICE_WATCHER");
            uint256 priceweight =  IPriceWatcher(priceWatcher).findPairPriceWeight(_pair);
            rateRatio = rateRatioBase + (rateRatioAdditional * priceweight / 1e6);

            //get greater of underlying, sfrxusd, or minimum
            underlyingRate = underlyingRate;
            uint256 riskFreeRate = sfrxusdRates();
            _ratePerSecond = minimumRate > riskFreeRate ? minimumRate : riskFreeRate;
            _ratePerSecond = underlyingRate > riskFreeRate ? underlyingRate : riskFreeRate;
            _ratePerSecond = _ratePerSecond * rateRatio / 1e18;
        }
    }

    //get swap amount out of a given route
    function getSwapRouteAmountOut(uint256 _amount, address _swapper, address[] calldata _path) public view returns(uint256 _returnAmount){
        _returnAmount = _amount;
        for(uint256 i=0; i < _path.length-1;){
            (address swappool, int32 tokenInIndex, int32 tokenOutIndex, uint32 swaptype) = ISwapper(_swapper).swapPools(_path[i],_path[i+1]);

            if(swaptype == TYPE_UNDEFINED){
                //assume if i is 0 we want to withdraw
                //assume if i is anything else we want to deposit

                
                if(i==0){
                    swappool = _path[i]; //use current index as the 4626 vault to withdraw from
                    swaptype = TYPE_WITHDRAW;
                }else{
                    swappool = _path[i+1]; //use next index as the 4626 vault to deposit to
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

        //get borrow shares/amount
        uint256 userBorrowShares = IResupplyPair(_pair).userBorrowShares(_account);
        uint256 borrowerAmount = IResupplyPair(_pair).toBorrowAmount(userBorrowShares, true, true);

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

    //check if a user is solvent after a theoretical leveraged borrow
    //maxltv passed in to simulate enforcing a certain CR
    function isSolventAfterLeverage(address _pair, uint256 _maxLTV, address _account, uint256 _addUnderlying, uint256 _borrowAmount, uint256 _slippage, address _swapper, address[] calldata _path) external returns(bool, uint256, uint256, uint256){

        //get borrow shares/amount
        uint256 userBorrowShares = IResupplyPair(_pair).userBorrowShares(_account);
        uint256 borrowerAmount = IResupplyPair(_pair).toBorrowAmount(userBorrowShares, true, true);

        //add the new borrow amount
        borrowerAmount += _borrowAmount;
        
        //get collateral
        uint256 collateralAmount = IResupplyPair(_pair).userCollateralBalance(_account);
        address collateralVault = IResupplyPair(_pair).collateral();

        //add underlying
        if(_addUnderlying > 0){
            collateralAmount += IERC4626(collateralVault).previewDeposit(_addUnderlying);
        }

        //get exchange rate of the amount borrowed to collateral amount
        uint256 collateralReceived = getSwapRouteAmountOut(_borrowAmount, _swapper, _path);
        //assume a reduction of the returned amount defined by slippage
        collateralReceived = collateralReceived * _slippage / 1e18;

        //add to collateral amount
        collateralAmount += collateralReceived;


        //get exchange rate
        (address oracle, , ) = IResupplyPair(_pair).exchangeRateInfo();
        uint256 exchangeRate = IOracle(oracle).getPrices(collateralVault);
        //convert price of collateral as debt is priced in terms of collateral amount (inverse)
        exchangeRate = 1e36 / exchangeRate;

        uint256 _ltv = ((borrowerAmount * exchangeRate * LTV_PRECISION) / EXCHANGE_PRECISION) / collateralAmount;
        return (_ltv <= _maxLTV, _ltv, borrowerAmount, collateralAmount);
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
        if(cbRatio == 0){
            cbRatio = 1e18; //if no collateal yet, just pad by 1e18
        }
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
