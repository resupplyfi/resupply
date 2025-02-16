// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IRewardHandler } from "src/interfaces/IRewardHandler.sol";
import { CoreOwnable } from 'src/dependencies/CoreOwnable.sol';
import { EpochTracker } from 'src/dependencies/EpochTracker.sol';
import { ICore } from "src/interfaces/ICore.sol";

//Fee deposit to collect/track fees and distribute
contract FeeDeposit is CoreOwnable, EpochTracker {
    using SafeERC20 for IERC20;

    address public immutable registry;
    address public immutable feeToken;

    address public operator;

    uint256 public lastDistributedEpoch;

    event FeesDistributed(address indexed _address, uint256 _amount);
    event ReceivedRevenue(address indexed _address, uint256 _fees, uint256 _otherFees);
    event SetOperator(address oldAddress, address newAddress);

    constructor(address _core, address _feeToken) CoreOwnable(_core) EpochTracker(_core){
        registry = ICore(_core).registry();
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
        uint256 currentEpoch = getEpoch();
        require(currentEpoch > lastDistributedEpoch, "!new epoch");

        lastDistributedEpoch = currentEpoch;
        uint256 amount = IERC20(feeToken).balanceOf(address(this));
        address _operator = operator;
        IERC20(feeToken).safeTransfer(_operator, amount);
        emit FeesDistributed(_operator,amount);
    }

    function incrementPairRevenue(uint256 _fees, uint256 _otherFees) external{
        //ensure caller is a registered pair
        require(IResupplyRegistry(registry).pairsByName(IERC20Metadata(msg.sender).name()) == msg.sender, "!regPair");

        emit ReceivedRevenue(msg.sender, _fees, _otherFees);

        //pass interest fees to handler to adjust reward weighting
        //note: only pass interest based fees
        IRewardHandler(IResupplyRegistry(registry).rewardHandler()).setPairWeight(msg.sender, _fees);
    }
}