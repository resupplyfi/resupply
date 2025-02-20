// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IResupplyPair } from "../interfaces/IResupplyPair.sol";
import { IResupplyRegistry } from "../interfaces/IResupplyRegistry.sol";
import { IERC4626 } from "../interfaces/IERC4626.sol";

interface IConvexPoolUtil {
    function rewardRates(uint256 _pid) external view returns (address[] memory tokens, uint256[] memory rates);
}

/*
This is a utility library which is mainly used for off chain calculations
*/
contract Utilities{

    address public constant convexPoolUtil = address(0x5Fba69a794F395184b5760DAf1134028608e5Cd1);

    constructor(){

    }

    //check if given account on given pair is solvent
    function isSolvent(address _pair, address _account) external view returns(bool){
        //todo
    }

    function apr(uint256 _rate, uint256 _priceOfReward, uint256 _priceOfDeposit) external view returns(uint256 _apr){
        return _rate * 365 days * _priceOfReward / _priceOfDeposit; 
    }

    //get rates for rewards received via collateral deposits
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
        uint256 cbRatio = totalCollateral * 1e36 / uint256(totalBorrow);

        uint256 rlength = rates.length;
        for(uint256 i = 0; i < rlength; i++){
            rates[i] = rates[i] * cbRatio / 1e36;
        }
    }

    //get emission reward rates per borrow share on a given pair
    function getPairRsupRates(address _pair) external view returns(uint256){
        //todo
    }

    //get emission rewards and protocol revenue share rates per pool share for the insurance pool
    function getInsurancePoolRewardRates() external view returns(address[] memory tokens, uint256[] memory rates){
        //todo
    }
}
