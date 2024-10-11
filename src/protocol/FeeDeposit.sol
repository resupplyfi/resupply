// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "../libraries/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IPairRegistry } from "../interfaces/IPairRegistry.sol";


//Fee deposit to collect/track fees and distribute
contract FeeDeposit is Ownable2Step{
    using SafeERC20 for IERC20;

    address public immutable registry;
    address public immutable feeToken;

    address public receiverPlatform;
    address public receiverInsurance;
    address public operator;

    uint256 public lastDistributedEpoch;

    uint256 private constant WEEK = 7 * 86400;

    event FeesDistributed(address indexed _address, uint256 _amount);

    constructor(address _owner, address _registry, address _feeToken) Ownable2Step(){
        registry = _registry;
        feeToken = _feeToken;
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

    function distributeFees(address _to, uint256 _amount) external onlyOperator{
        uint256 currentEpoch = block.timestamp/WEEK * WEEK;
        require(currentEpoch > lastDistributedEpoch, "!new epoch");

        lastDistributedEpoch = currentEpoch;
        IERC20(feeToken).safeTransfer(_to, _amount);
        emit FeesDistributed(_to,_amount);
    }

    function incrementPairRevenue(uint256 _amount) external{
        //ensure caller is a registered pair
        require(IPairRegistry(registry).deployedPairsByName(IERC20Metadata(msg.sender).name()) == msg.sender, "!regPair");

        //TODO track pair revenue
        // trailing by timespan? epoch based?
        //callable whenever? callable once per epoch?
        /* example
        uint _epoch = getCurrentEpoch();
        _incrementEpochRevenuePerPair(pair, _epoch, interestEarned);
        address _baseAsset = getBaseAsset(pair.asset());
        _incrementEpochRevenuePerBaseAsset(_asset, _epoch, interestEarned);
        */
    }
}