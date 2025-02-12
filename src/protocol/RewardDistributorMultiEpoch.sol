// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


//abstract reward handling to attach to another contract
//supports an epoch system for supply changes
abstract contract RewardDistributorMultiEpoch is ReentrancyGuard{
    using SafeERC20 for IERC20;

    struct EarnedData {
        address token;
        uint256 amount;
    }

    struct RewardType {
        address reward_token;
        bool is_non_claimable; //a bit unothrodox setting but need to block claims on our redemption tokens as they will be processed differently
        uint256 reward_remaining;
    }

    //rewards
    RewardType[] public rewards;
    uint256 public currentRewardEpoch;
    mapping(address => uint256) public userRewardEpoch; //account -> epoch
    mapping(uint256 => mapping(address => uint256)) public global_reward_integral; //epoch -> token -> integral
    mapping(uint256 => mapping(address => mapping(address => uint256))) public reward_integral_for;// epoch -> token -> account -> integral
    mapping(address => mapping(address => uint256)) public claimable_reward;//token -> account -> claimable
    mapping(address => uint256) public rewardMap;
    mapping(address => address) public rewardRedirect;
    
    uint256 constant private PRECISION = 1e22;

    //events
    event RewardPaid(address indexed _user, address indexed _rewardToken, address indexed _receiver, uint256 _rewardAmount);
    event RewardAdded(address indexed _rewardToken);
    event RewardInvalidated(address indexed _rewardToken);
    event RewardRedirected(address indexed _account, address _forward);
    event NewEpoch(uint256 indexed _epoch);

    constructor() {

    }

    modifier onlyRewardManager() {
        require(_isRewardManager(), "!rewardManager");
        _;
    }

/////////
//  Abstract functions
////////

    function _isRewardManager() internal view virtual returns(bool);

    function _fetchIncentives() internal virtual;

    function _totalRewardShares() internal view virtual returns(uint256);

    function _userRewardShares(address _account) internal view virtual returns(uint256);

    function _increaseUserRewardEpoch(address _account, uint256 _currentUserEpoch) internal virtual;

    function _checkAddToken(address _address) internal view virtual returns(bool);
//////////

    function maxRewards() public pure virtual returns(uint256){
        return 15;
    }

    //register an extra reward token to be handled
    function addExtraReward(address _token) external onlyRewardManager nonReentrant{
        //add to reward list
        _insertRewardToken(_token);
    }

    //insert a new reward, ignore if already registered or invalid
    function _insertRewardToken(address _token) internal{
        if(_token == address(this) || _token == address(0) || !_checkAddToken(_token)){
            //dont allow reward tracking of the staking token or invalid address
            return;
        }

        //add to reward list if new
        if(rewardMap[_token] == 0){
            //check reward count for new additions
            require(rewards.length < maxRewards(), "max rewards");

            //set token
            RewardType storage r = rewards.push();
            r.reward_token = _token;
            
            //set map index after push (mapped value is +1 of real index)
            rewardMap[_token] = rewards.length;

            //workaround: transfer 0 to self so that earned() reports correctly
            //with new tokens
            if(_token.code.length > 0){
                IERC20(_token).safeTransfer(address(this), 0);
            }else{
                //non contract address added? invalidate
                _invalidateReward(_token);
            }

            emit RewardAdded(_token);
        }else{
            //get previous used index of given token
            //this ensures that reviving can only be done on the previous used slot
            uint256 index = rewardMap[_token];
            //index is rewardMap minus one
            RewardType storage reward = rewards[index-1];
            //check if it was invalidated
            if(reward.reward_token == address(0)){
                //revive
                reward.reward_token = _token;
                emit RewardAdded(_token);
            }
        }
    }

    //allow invalidating a reward if the token causes trouble in calcRewardIntegral
    function invalidateReward(address _token) external onlyRewardManager nonReentrant{
        _invalidateReward(_token);
    }

    function _invalidateReward(address _token) internal{
        uint256 index = rewardMap[_token];
        if(index > 0){
            //index is registered rewards minus one
            RewardType storage reward = rewards[index-1];
            require(reward.reward_token == _token, "!mismatch");
            //set reward token address to 0, integral calc will now skip
            reward.reward_token = address(0);
            emit RewardInvalidated(_token);
        }
    }

    //get reward count
    function rewardLength() external view returns(uint256) {
        return rewards.length;
    }

    //calculate and record an account's earnings of the given reward.  if _claimTo is given it will also claim.
    function _calcRewardIntegral(uint256 _epoch, uint256 _currentEpoch, uint256 _index, address _account, address _claimTo) internal{
        RewardType storage reward = rewards[_index];
        address rewardToken = reward.reward_token;
        //skip invalidated rewards
        //if a reward token starts throwing an error, calcRewardIntegral needs a way to exit
        if(rewardToken == address(0)){
           return;
        }

        //get difference in balance and remaining rewards
        //getReward is unguarded so we use reward_remaining to keep track of how much was actually claimed since last checkpoint
        uint256 bal = IERC20(rewardToken).balanceOf(address(this));
        uint256 remainingRewards = reward.reward_remaining;
        
        //update the global integral but only for the current epoch
        if (_epoch == _currentEpoch && _totalRewardShares() > 0 && bal > remainingRewards) {
            uint256 rewardPerToken = ((bal - remainingRewards) * PRECISION / _totalRewardShares());
            if(rewardPerToken > 0){
                //increase integral
                global_reward_integral[_epoch][rewardToken] += rewardPerToken;
            }else{
                //set balance as current reward_remaining to let dust grow
                bal = remainingRewards;
            }
        }

        uint256 reward_global = global_reward_integral[_epoch][rewardToken];

        if(_account != address(0)){
            //update user integrals
            uint userI = reward_integral_for[_epoch][rewardToken][_account];
            if(_claimTo != address(0) || userI < reward_global){
                //_claimTo address non-zero means its a claim 
                // only allow claims if current epoch and if the reward allows it
                if(_epoch == _currentEpoch && _claimTo != address(0) && !reward.is_non_claimable){
                    uint256 receiveable = claimable_reward[rewardToken][_account] + (_userRewardShares(_account) * (reward_global - userI) / PRECISION);
                    if(receiveable > 0){
                        claimable_reward[rewardToken][_account] = 0;
                        IERC20(rewardToken).safeTransfer(_claimTo, receiveable);
                        emit RewardPaid(_account, rewardToken, _claimTo, receiveable);
                        //remove what was claimed from balance
                        bal -= receiveable;
                    }
                }else{
                    claimable_reward[rewardToken][_account] = claimable_reward[rewardToken][_account] + ( _userRewardShares(_account) * (reward_global - userI) / PRECISION);
                }
                reward_integral_for[_epoch][rewardToken][_account] = reward_global;
            }
        }


        //update remaining reward so that next claim can properly calculate the balance change
        //claims and tracking new rewards should only happen on current epoch
        if(_epoch == _currentEpoch && bal != remainingRewards){
            reward.reward_remaining = bal;
        }
    }

    function _increaseRewardEpoch() internal{
        //final checkpoint for this epoch
        _checkpoint(address(0), address(0), type(uint256).max);

        //move epoch up
        uint256 newEpoch = currentRewardEpoch + 1;
        currentRewardEpoch = newEpoch;

        emit NewEpoch(newEpoch);
    }

    //checkpoint without claiming
    function _checkpoint(address _account) internal {
        //checkpoint without claiming by passing address(0)
        //default to max as most operations such as deposit/withdraw etc needs to fully sync beforehand
        _checkpoint(_account, address(0), type(uint256).max);
    }

    //checkpoint with claim
    function _checkpoint(address _account, address _claimTo, uint256 _maxloops) internal {
        //claim rewards first
        _fetchIncentives();

        uint256 globalEpoch = currentRewardEpoch;
        uint256 rewardCount = rewards.length;

        for (uint256 loops = 0; loops < _maxloops;) {
            uint256 userEpoch = globalEpoch;

            if(_account != address(0)){
                //take user epoch
                userEpoch = userRewardEpoch[_account];

                //if no shares then jump to current epoch
                if(userEpoch != globalEpoch && _userRewardShares(_account) == 0){
                    userEpoch = globalEpoch;
                    userRewardEpoch[_account] = userEpoch;
                }
            }
            
            //calc reward integrals
            for(uint256 i = 0; i < rewardCount;){
                _calcRewardIntegral(userEpoch, globalEpoch, i,_account,_claimTo);
                unchecked { i += 1; }
            }
            if(userEpoch < globalEpoch){
                _increaseUserRewardEpoch(_account, userEpoch);
            }else{
                return;
            }
            unchecked { loops += 1; }
        }
    }

    //manually checkpoint a user account
    function user_checkpoint(address _account, uint256 _epochloops) external nonReentrant returns(bool) {
        _checkpoint(_account, address(0), _epochloops);
        return true;
    }

    //get earned token info
    //change ABI to view to use this off chain
    function earned(address _account) public nonReentrant virtual returns(EarnedData[] memory claimable) {
        
        //because this is a state mutative function
        //we can simplify the earned() logic of all rewards (internal and external)
        //and allow this contract to be agnostic to outside reward contract design
        //by just claiming everything and updating state via _checkpoint()
        _checkpoint(_account);
        uint256 rewardCount = rewards.length;
        claimable = new EarnedData[](rewardCount);

        for (uint256 i = 0; i < rewardCount;) {
            RewardType storage reward = rewards[i];

            //skip invalidated and non claimable rewards
            if(reward.reward_token == address(0) || reward.is_non_claimable){
                unchecked{ i += 1; }
                continue;
            }
    
            claimable[i].amount = claimable_reward[reward.reward_token][_account];
            claimable[i].token = reward.reward_token;

            unchecked{ i += 1; }
        }
        return claimable;
    }

    //set any claimed rewards to automatically go to a different address
    //set address to zero to disable
    function setRewardRedirect(address _to) external nonReentrant{
        rewardRedirect[msg.sender] = _to;
        emit RewardRedirected(msg.sender, _to);
    }

    //claim reward for given account (unguarded)
    function getReward(address _account) public virtual nonReentrant {
        //check if there is a redirect address
        address redirect = rewardRedirect[_account];
        if(redirect != address(0)){
            _checkpoint(_account, redirect, type(uint256).max);
        }else{
            //claim directly in checkpoint logic to save a bit of gas
            _checkpoint(_account, _account, type(uint256).max);
        }
    }

    //claim reward for given account and forward (guarded)
    function getReward(address _account, address _forwardTo) public virtual nonReentrant{
        //in order to forward, must be called by the account itself
        require(msg.sender == _account, "!self");
        require(_forwardTo != address(0), "fwd address cannot be 0");
        //use _forwardTo address instead of _account
        _checkpoint(_account, _forwardTo, type(uint256).max);
    }
}