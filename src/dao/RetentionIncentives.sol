// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/*
   ____            __   __        __   _
  / __/__ __ ___  / /_ / /  ___  / /_ (_)__ __
 _\ \ / // // _ \/ __// _ \/ -_)/ __// / \ \ /
/___/ \_, //_//_/\__//_//_/\__/ \__//_/ /_\_\
     /___/

* Synthetix: BaseRewardPool.sol
*
* Docs: https://docs.synthetix.io/
*
*
* MIT License
* ===========
*
* Copyright (c) 2020 Synthetix
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in all
* copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
*/

import "../libraries/MathUtil.sol";
import { IResupplyRegistry } from "../interfaces/IResupplyRegistry.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "../libraries/SafeERC20.sol";
import { CoreOwnable } from '../dependencies/CoreOwnable.sol';
import { IERC20Decimals } from "../interfaces/IERC20Decimals.sol";
import { IInsurancePool } from "../interfaces/IInsurancePool.sol";

/*
 Reward contract with pre-set address balances and a lookup to current Insurance Pool balance
*/
contract RetentionIncentives is CoreOwnable {
    using SafeERC20 for IERC20;

    uint256 public constant duration = 7 days;

    IERC20 public immutable rewardToken;
    address public immutable registry;
    address public immutable insurancePool;

    uint256 public periodFinish;
    uint256 public rewardRate;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public queuedRewards;
    uint256 public currentRewards;
    uint256 public historicalRewards;
    address public operator;

    bool public isFinalized;
    address public rewardHandler;
    
    uint256 private _totalSupply;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;
    mapping(address => uint256) private _balances;
    mapping(address => uint256) private originalBalanceOf;
    mapping(address => address) public rewardRedirect;
    
    event RewardAdded(uint256 reward);
    event WeightSet(address indexed user, uint256 oldWeight, uint256 newWeight);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardRedirected(address indexed user, address redirect);

    event Finalize();
    event SetRewardHandler(address indexed handler);
    event SetOperator(address indexed operator);

    constructor(address _core, address _registry, address _rewardToken, address _insurancePool) CoreOwnable(_core){
        registry = _registry;
        rewardToken = IERC20(_rewardToken);
        require(IERC20Decimals(_rewardToken).decimals() == 18, "18 decimals required"); // Guard against precision loss.
        insurancePool = _insurancePool;
    }

    modifier onlyRewardManager() {
        require(msg.sender == owner() || msg.sender == rewardHandler, "!rewardManager");
        _;
    }

    modifier onlyOperator() {
        require(msg.sender == owner() || msg.sender == operator, "!operator");
        _;
    }

    function setRewardHandler(address _handler) external onlyOwner{
        require(_handler != address(0),"invalid address");

        rewardHandler = _handler;
        emit SetRewardHandler(_handler);
    }

    function setOperator(address _operator) external onlyOwner{
        require(_operator != address(0),"!zeroaddress");

        operator = _operator;
        emit SetOperator(_operator);
    }

    //one time setter
    function setAddressBalances(address[] calldata _addressList, uint256[] calldata _balanceList) external {
        require(!isFinalized, "finalized");

        uint256 tsupply;
        require(_totalSupply == 0, "!tsupply");
        uint256 length = _addressList.length;
        require(length == _balanceList.length, "!length");
        
        for(uint256 i; i < length; ){
            emit WeightSet(_addressList[i], 0, _balanceList[i]);

            unchecked{
                require(originalBalanceOf[_addressList[i]] == 0, "!duplicate");
                originalBalanceOf[_addressList[i]] = _balanceList[i];
                _balances[_addressList[i]] = _balanceList[i];
                tsupply += _balanceList[i];
            
                i++;
            }
        }
        _totalSupply = tsupply; //set supply

        isFinalized = true;
        emit Finalize();
    }


    //total supply
    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    //balance of an account
    function balanceOf(address _account) public view returns (uint256) {
        return _balances[_account];
    }

    //checkpoint earned rewards modifier
    modifier updateReward(address _account) {

        _updateReward(_account);

        _;
    }

    function _updateReward(address _account) internal{

        uint256 rewardPerToken = rewardPerToken();
        rewardPerTokenStored = rewardPerToken;
        lastUpdateTime = lastTimeRewardApplicable();

        if (_account != address(0)) {
            //first update earned rewards
            rewards[_account] = earned(_account);
            userRewardPerTokenPaid[_account] = rewardPerToken;

            //update balances by looking at insurance pool
            uint256 ipShares = IInsurancePool(insurancePool).balanceOf(_account);
            uint256 currentBalance = _balances[_account];
            
            if(ipShares < currentBalance){
                emit WeightSet(_account, currentBalance, ipShares);

                //shares went down, update
                _balances[_account] = ipShares;
                _totalSupply = _totalSupply + ipShares - currentBalance;
            }
        }
    }
    
    function checkpoint_multiple(address[] calldata _accounts) external onlyOperator {

        uint256 length = _accounts.length;
        for(uint256 i; i < length; ){
           _updateReward(_accounts[i]);

            unchecked{
                i++;
            }
        }
    }

    //checkpoint a given user
    function user_checkpoint(address _account) public updateReward(_account){

    }

    //claim time to period finish
    function lastTimeRewardApplicable() public view returns (uint256) {
        return MathUtil.min(block.timestamp, periodFinish);
    }

    //rewards per weight
    function rewardPerToken() public view returns (uint256) {
        if (totalSupply() == 0) {
            return rewardPerTokenStored;
        }
        return rewardPerTokenStored + ((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18 / totalSupply());
    }

    //earned rewards for given account
    function earned(address _account) public view returns (uint256) {
        return rewards[_account] + (balanceOf(_account) * (rewardPerToken() - userRewardPerTokenPaid[_account]) / 1e18);
    }

    //set any claimed rewards to automatically go to a different address
    //set address to zero to disable
    function setRewardRedirect(address _to) external{
        rewardRedirect[msg.sender] = _to;
        emit RewardRedirected(msg.sender, _to);
    }

    function getReward() external{
        getReward(msg.sender);
    }

    //claim reward for given account (unguarded)
    function getReward(address _account) public updateReward(_account){
        uint256 reward = rewards[_account]; //earned is called in updateReward and thus up to date
        if (reward > 0) {
            rewards[_account] = 0;
            emit RewardPaid(_account, reward);
            //check if there is a redirect address
            address redirect = rewardRedirect[_account];
            if(redirect != address(0)){
                rewardToken.safeTransfer(redirect, reward);
            }else{
                //normal claim to account address
                rewardToken.safeTransfer(_account, reward);
            }
        }
    }

    //claim reward for given account and forward (guarded)
    function getReward(address _account, address _forwardTo) external updateReward(_account){
        //in order to forward, must be called by the account itself
        require(msg.sender == _account, "!self");
        require(_forwardTo != address(0), "fwd address cannot be 0");

        //claim to _forwardTo
        uint256 reward = rewards[_account]; //earned is called in updateReward and thus up to date
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardToken.safeTransfer(_forwardTo, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    //outside address add to rewards
    function donate(uint256 _amount) external returns(bool){
        IERC20(rewardToken).safeTransferFrom(msg.sender, address(this), _amount);
        queuedRewards += _amount;
        return true;
    }

    //distributor can add more rewards and start new reward cycle
    function queueNewRewards(uint256 _rewards) external onlyRewardManager returns(bool){

        require(isFinalized, "must finalize first");

        //pull
        if(_rewards > 0){
            IERC20(rewardToken).safeTransferFrom(msg.sender, address(this), _rewards);
        }

        //notify pulled + queued
        notifyRewardAmount(_rewards + queuedRewards);
        //reset queued
        queuedRewards = 0;
        return true;
    }


    //internal: start new reward cycle
    function notifyRewardAmount(uint256 reward)
        internal
        updateReward(address(0))
    {
        historicalRewards += reward;
        if (block.timestamp >= periodFinish) {
            rewardRate = reward / duration;
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            reward += leftover;
            rewardRate = reward / duration;
        }
        currentRewards = reward;
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + duration;
        emit RewardAdded(reward);
    }
}