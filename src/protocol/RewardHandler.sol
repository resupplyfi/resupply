// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { SafeERC20 } from "../libraries/SafeERC20.sol";


//abstract reward handling to attach to another contract
abstract contract RewardHandler is ReentrancyGuard{
    using SafeERC20 for IERC20;

    struct EarnedData {
        address token;
        uint256 amount;
    }

    struct RewardType {
        address reward_token;
        uint256 reward_integral;
        uint256 reward_remaining;
        bool is_non_claimable; //a bit unothrodox setting but need to block claims on our redemption tokens as they will be processed differently
    }

    //rewards
    RewardType[] public rewards;
    mapping(address => mapping(address => uint256)) public reward_integral_for;// token -> account -> integral
    mapping(address => mapping(address => uint256)) public claimable_reward;//token -> account -> claimable
    mapping(address => uint256) public rewardMap;
    mapping(address => address) public rewardRedirect;
    uint256 public constant maxRewards = 12;


    //events
    event RewardPaid(address indexed _user, address indexed _rewardToken, address indexed _receiver, uint256 _rewardAmount);
    event RewardAdded(address indexed _rewardToken);
    event RewardInvalidated(address _rewardToken);
    event RewardRedirected(address indexed _account, address _forward);

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

    function _claimPoolRewards() internal virtual;

    function _totalRewardShares() internal view virtual returns(uint256);

    function _userRewardShares(address _account) internal view virtual returns(uint256);

//////////

    //register an extra reward token to be handled
    function addExtraReward(address _token) external onlyRewardManager nonReentrant{
        //add to reward list
        _insertRewardToken(_token);
    }

    //insert a new reward, ignore if already registered or invalid
    function _insertRewardToken(address _token) internal{
        if(_token == address(this) || _token == address(0)){
            //dont allow reward tracking of the staking token or invalid address
            return;
        }

        //add to reward list if new
        if(rewardMap[_token] == 0){
            //check reward count for new additions
            require(rewards.length < maxRewards, "max rewards");

            //set token
            RewardType storage r = rewards.push();
            r.reward_token = _token;
            
            //set map index after push (mapped value is +1 of real index)
            rewardMap[_token] = rewards.length;

            //workaround: transfer 0 to self so that earned() reports correctly
            //with new tokens
            if(_token.code.length > 0){
                try IERC20(_token).transfer(address(this), 0){}catch{
                    //cant transfer? invalidate
                    _invalidateReward(_token);
                }
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
    function _calcRewardIntegral(uint256 _index, address _account, address _claimTo) internal{
        RewardType storage reward = rewards[_index];
        //skip invalidated rewards
        //if a reward token starts throwing an error, calcRewardIntegral needs a way to exit
        if(reward.reward_token == address(0)){
           return;
        }

        //get difference in balance and remaining rewards
        //getReward is unguarded so we use reward_remaining to keep track of how much was actually claimed since last checkpoint
        uint256 bal = IERC20(reward.reward_token).balanceOf(address(this));


        //update the global integral
        if (_totalRewardShares() > 0 && bal > reward.reward_remaining) {
            reward.reward_integral = reward.reward_integral + ((bal - reward.reward_remaining) * 1e20 / _totalRewardShares());
        }

        //update user integrals
        uint userI = reward_integral_for[reward.reward_token][_account];
        if(_claimTo != address(0) || userI < reward.reward_integral){
            //_claimTo address non-zero means its a claim 
            if(_claimTo != address(0) && !reward.is_non_claimable){
                uint256 receiveable = claimable_reward[reward.reward_token][_account] + (_userRewardShares(_account) * (reward.reward_integral - userI) / 1e20);
                if(receiveable > 0){
                    claimable_reward[reward.reward_token][_account] = 0;
                    IERC20(reward.reward_token).safeTransfer(_claimTo, receiveable);
                    emit RewardPaid(_account, reward.reward_token, _claimTo, receiveable);
                    //remove what was claimed from balance
                    bal -= receiveable;
                }
            }else{
                claimable_reward[reward.reward_token][_account] = claimable_reward[reward.reward_token][_account] + ( _userRewardShares(_account) * (reward.reward_integral - userI) / 1e20);
            }
            reward_integral_for[reward.reward_token][_account] = reward.reward_integral;
        }


        //update remaining reward so that next claim can properly calculate the balance change
        if(bal != reward.reward_remaining){
            reward.reward_remaining = bal;
        }
    }

    //checkpoint without claiming
    function _checkpoint(address _account) internal {
        //checkpoint without claiming by passing address(0)
        _checkpoint(_account, address(0));
    }

    //checkpoint with claim
    function _checkpoint(address _account, address _claimTo) internal nonReentrant{
        //claim rewards first
        _claimPoolRewards();

        //calc reward integrals
        uint256 rewardCount = rewards.length;
        for(uint256 i = 0; i < rewardCount; i++){
           _calcRewardIntegral(i,_account,_claimTo);
        }
    }

    //manually checkpoint a user account
    function user_checkpoint(address _account) external returns(bool) {
        _checkpoint(_account);
        return true;
    }

    //get earned token info
    //change ABI to view to use this off chain
    function earned(address _account) external returns(EarnedData[] memory claimable) {
        
        //because this is a state mutative function
        //we can simplify the earned() logic of all rewards (internal and external)
        //and allow this contract to be agnostic to outside reward contract design
        //by just claiming everything and updating state via _checkpoint()
        _checkpoint(_account);
        uint256 rewardCount = rewards.length;
        claimable = new EarnedData[](rewardCount);

        for (uint256 i = 0; i < rewardCount; i++) {
            RewardType storage reward = rewards[i];

            //skip invalidated and non claimable rewards
            if(reward.reward_token == address(0) || reward.is_non_claimable){
                continue;
            }
    
            claimable[i].amount = claimable_reward[reward.reward_token][_account];
            claimable[i].token = reward.reward_token;
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
    function getReward(address _account) external {
        //check if there is a redirect address
        if(rewardRedirect[_account] != address(0)){
            _checkpoint(_account, rewardRedirect[_account]);
        }else{
            //claim directly in checkpoint logic to save a bit of gas
            _checkpoint(_account, _account);
        }
    }

    //claim reward for given account and forward (guarded)
    function getReward(address _account, address _forwardTo) external {
        //in order to forward, must be called by the account itself
        require(msg.sender == _account, "!self");
        //use _forwardTo address instead of _account
        _checkpoint(_account,_forwardTo);
    }
}