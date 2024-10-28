// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "../libraries/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IPairRegistry } from "../interfaces/IPairRegistry.sol";
import { IRewardHandler } from "../interfaces/IRewardHandler.sol";
import { CoreOwnable } from '../dependencies/CoreOwnable.sol';



//Fee deposit to collect/track fees and distribute
contract FeeDeposit is CoreOwnable{
    using SafeERC20 for IERC20;

    address public immutable registry;
    address public immutable feeToken;

    address public receiverPlatform;
    address public receiverInsurance;
    address public operator;

    uint256 public lastDistributedEpoch;

    uint256 private constant WEEK = 7 * 86400;

    event FeesDistributed(address indexed _address, uint256 _amount);
    event ReceivedRevenue(address indexed _address, uint256 _fees, uint256 _otherFees);
    event SetOperator(address oldAddress, address newAddress);

    constructor(address _core, address _registry, address _feeToken) CoreOwnable(_core){
        registry = _registry;
        feeToken = _feeToken;
    }

    modifier onlyOperator() {
        require(operator == msg.sender, "!operator");
        _;
    }

    function setOperator(address _newAddress) external onlyOwner{
        emit SetOperator(operator, _newAddress);
        operator = _newAddress;
    }

    function distributeFees() external onlyOperator{
        uint256 currentEpoch = block.timestamp/WEEK * WEEK;
        require(currentEpoch > lastDistributedEpoch, "!new epoch");

        lastDistributedEpoch = currentEpoch;
        uint256 amount = IERC20(feeToken).balanceOf(address(this));
        IERC20(feeToken).safeTransfer(operator, amount);
        emit FeesDistributed(operator,amount);
    }

    function incrementPairRevenue(uint256 _fees, uint256 _otherFees) external{
        //ensure caller is a registered pair
        require(IPairRegistry(registry).deployedPairsByName(IERC20Metadata(msg.sender).name()) == msg.sender, "!regPair");

        emit ReceivedRevenue(msg.sender, _fees, _otherFees);

        //pass interest fees to handler to adjust reward weighting
        //note: only pass interest based fees
        IRewardHandler(IPairRegistry(registry).rewardHandler()).setPairWeight(msg.sender, _fees);
    }
}