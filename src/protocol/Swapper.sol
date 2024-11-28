// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interfaces/ICurveExchange.sol";

import { IERC4626 } from "../interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "../libraries/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { CoreOwnable } from "../dependencies/CoreOwnable.sol";

contract Swapper is CoreOwnable, ReentrancyGuard{
    using SafeERC20 for IERC20;

    struct SwapInfo{
        address swappool;
        int32 tokenInIndex;
        int32 tokenOutIndex;
        bool isDeposit;
    }

    mapping(address => mapping(address => SwapInfo)) public swapPools;//token in -> token out -> info
    
    //events
    event PairAdded(address indexed _tokenIn, address indexed _tokenOut, SwapInfo _info);


    constructor(address _core) CoreOwnable(_core){
    }

    function addPairing(address _tokenIn, address _tokenOut, SwapInfo calldata _swapInfo) external onlyOwner{
        //add to mapping
        swapPools[_tokenIn][_tokenOut] = _swapInfo;
        //approve tokenIn so it can be swapped
        IERC20(_tokenIn).approve(_swapInfo.swappool, type(uint256).max);

        emit PairAdded(_tokenIn, _tokenOut, _swapInfo);
    }

    function swap(
        address account,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to
    ) external returns (uint256 amountOut){

        //todo: could save an approval if pair just sends directly to this swapper
        IERC20(path[0]).safeTransferFrom(msg.sender, address(this), amountIn);

        for(uint256 i=0; i < path.length-1;){
            SwapInfo memory swapinfo = swapPools[path[i]][path[i+1]];
            uint256 balanceIn = IERC20(path[i]).balanceOf(address(this));
            //if final swap, send back to msg.sender
            address returnAddress = i == path.length - 2 ? to : address(this);

            if(swapinfo.isDeposit){
                //if set as a deposit, use 4626 interface
                IERC4626(swapinfo.swappool).deposit(balanceIn, returnAddress);
            }else{
                //swap with curve pool
                //note: the resupply pair will check final slippage
                ICurveExchange(swapinfo.swappool).exchange(int128(swapinfo.tokenInIndex), int128(swapinfo.tokenOutIndex), balanceIn, 0, returnAddress);
            }
            unchecked{ i += 1;}
        }
    }
}