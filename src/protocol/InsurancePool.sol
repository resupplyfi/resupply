// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "../libraries/SafeERC20.sol";
import { IMintable } from "../interfaces/IMintable.sol";
import { RewardDistributorMultiEpoch } from "./RewardDistributorMultiEpoch.sol";
import { IResupplyRegistry } from "../interfaces/IResupplyRegistry.sol";
import { CoreOwnable } from '../dependencies/CoreOwnable.sol';

contract InsurancePool is RewardDistributorMultiEpoch, CoreOwnable{
    using SafeERC20 for IERC20;

    address immutable public asset;
    address immutable public registry;
    
    mapping(address => uint256) private _balances;
    uint256 private _totalSupply;
    uint256 constant public SHARE_REFACTOR_PRECISION = 1e12;

    uint256 public minimumHeldAssets = 10_000 * 1e18;

    uint256 public withdrawTime = 7 days;
    uint256 public withdrawTimeLimit = 1 days;
    mapping(address => uint256) public withdrawQueue;

    address public immutable emissionsReceiver;
    uint256 public constant MAX_WITHDRAW_DELAY = 14 days;

    //events
    event Deposit(
        address indexed sender,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    event Withdraw(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256 shares,
        uint256 assets
    );

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Cooldown(address indexed account, uint256 amount, uint256 end);
    event ExitCancel(address indexed account);
    event WithdrawTimersUpdated(uint256 withdrawTime, uint256 withdrawWindow);
    event MinimumHeldAssetsUpdated(uint256 minimumAssets);

    constructor(address _core, address _registry, address _asset, address[] memory _rewards, address _emissionsReceiver) CoreOwnable(_core){
        asset = _asset;
        registry = _registry;
        emissionsReceiver = _emissionsReceiver;
        //initialize rewards list with passed in reward tokens
        //NOTE: slot 0 should be emission based extra reward
        for(uint256 i = 0; i < _rewards.length;){
            _insertRewardToken(_rewards[i]);
            unchecked { i += 1; }
        }
        

        //mint unbacked shares to this address
        //deployment should send the outstanding amount
        _mint(address(this), 1e18);
    }

    function name() external pure returns (string memory){
        return "Resupply Insurance Pool";
    }

    function symbol() external pure returns (string memory){
        return "reIP";
    }

    function decimals() external pure returns (uint8){
        return 18;
    }

    /// @notice set unlock length and withdraw window
    /// @param _withdrawLength time to unlock
    /// @param _withdrawWindow time to withdraw after unlock
    function setWithdrawTimers(uint256 _withdrawLength, uint256 _withdrawWindow) external onlyOwner{
        require(_withdrawLength <= MAX_WITHDRAW_DELAY, "too high");
        withdrawTime = _withdrawLength;
        withdrawTimeLimit = _withdrawWindow;
        emit WithdrawTimersUpdated(_withdrawLength, _withdrawWindow);
    }

    /// @notice set a minimum amount of assets that must be kept from being burned
    /// @param _minimum the amount of assets to protect from burn
    function setMinimumHeldAssets(uint256 _minimum) external onlyOwner{
        require(_minimum >= 1e18, "too low");
        minimumHeldAssets = _minimum;
        emit MinimumHeldAssetsUpdated(_minimum);
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    /// @notice balance of a given account
    /// @param _account the user account
    function balanceOf(address _account) public view returns (uint256 userBalance) {
        userBalance = _balances[_account];

        uint256 globalEpoch = currentRewardEpoch;
        uint256 userEpoch = userRewardEpoch[_account];

        if(userEpoch < globalEpoch){
            //need to calculate balance while keeping this as a view function
            for(;;){
                //reduce shares by refactoring amount
                userBalance /= SHARE_REFACTOR_PRECISION;
                unchecked {
                    userEpoch += 1;
                }
                if(userEpoch == globalEpoch){
                    break;
                }
            }
        }
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint to the zero address");

        _totalSupply += amount;
        unchecked {
            // Overflow not possible: balance + amount is at most totalSupply + amount, which is checked above.
            _balances[account] += amount;
        }
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: burn from the zero address");

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
            // Overflow not possible: amount <= accountBalance <= totalSupply.
            _totalSupply -= amount;
        }

        emit Transfer(account, address(0), amount);
    }

    // ============================================================================================
    // Reward Implementation
    // ============================================================================================

    function _isRewardManager() internal view override returns(bool){
        return msg.sender == address(core)
        || msg.sender == IResupplyRegistry(registry).rewardHandler();
    }

    function _fetchIncentives() internal override{
        IResupplyRegistry(registry).claimInsuranceRewards();
    }

    function _totalRewardShares() internal view override returns(uint256){
        return _totalSupply;
    }

    function _userRewardShares(address _account) internal view override returns(uint256){
        return _balances[_account];
    }

    function _increaseUserRewardEpoch(address _account, uint256 _currentUserEpoch) internal override{
        //convert shares to next epoch shares
        //share refactoring will never be 0
        _balances[_account] = _balances[_account] / SHARE_REFACTOR_PRECISION;
        //update user reward epoch
        userRewardEpoch[_account] = _currentUserEpoch + 1;
    }

    function _checkAddToken(address _address) internal view override returns(bool){
        if(_address == asset) return false;
        return true;
    }

    //we cant limit reward types since collaterals could be sent as rewards
    //however reward lists growing too large is undesirable
    //governance should act if too many are added
    function maxRewards() public pure override returns(uint256){
        return type(uint256).max;
    }

    function maxBurnableAssets() public view returns(uint256){
        uint256 minimumHeld = minimumHeldAssets;
        uint256 _totalAssets = totalAssets();
        return _totalAssets > minimumHeld ? _totalAssets - minimumHeld : 0;
    }

    /// @notice burn underlying, liquidationHandler will send rewards in exchange
    /// @param _amount the amount to burn
    function burnAssets(uint256 _amount) external {
        require(msg.sender == IResupplyRegistry(registry).liquidationHandler(), "!liq handler");
        require(_amount <= maxBurnableAssets(), "!minimumAssets");

        IMintable(asset).burn(address(this), _amount);

        //if after many burns the amount to shares ratio has deteriorated too far, then refactor
        uint256 tsupply = _totalSupply;
        if(totalAssets() * SHARE_REFACTOR_PRECISION < tsupply){
            _increaseRewardEpoch(); //will do final checkpoint on previous total supply
            tsupply /= SHARE_REFACTOR_PRECISION;
            _totalSupply = tsupply;
        }
    }

    /// @notice deposit assets into the insurance pool
    /// @param _assets the amount of tokens to deposit
    /// @param _receiver the receiving address
    /// @return shares amount of shares minted
    function deposit(uint256 _assets, address _receiver) external nonReentrant returns (uint256 shares){
        //can not deposit if in withdraw queue, call cancel first
        require(withdrawQueue[_receiver] == 0,"withdraw queued");

        //checkpoint rewards before balance change
        _checkpoint(_receiver);
         if (_assets > 0) {
            shares = previewDeposit(_assets);
            if(shares > 0){
                _mint(_receiver, shares);
                IERC20(asset).safeTransferFrom(msg.sender, address(this), _assets);
                emit Deposit(msg.sender, _receiver, _assets, shares);
            }
        }
    }

    /// @notice mint shares
    /// @param _shares the amount of shares to mint
    /// @param _receiver the receving address
    /// @return assets amount of assets minted
    function mint(uint256 _shares, address _receiver) external nonReentrant returns (uint256 assets){
        //can not deposit if in withdraw queue, call cancel first
        require(withdrawQueue[_receiver] == 0,"withdraw queued");

        //checkpoint rewards before balance change
        _checkpoint(_receiver);
        if (_shares > 0) {
            assets = previewMint(_shares);
            if(assets > 0){
                _mint(_receiver, _shares);
                IERC20(asset).safeTransferFrom(msg.sender, address(this), assets);
                emit Deposit(msg.sender, _receiver, assets, _shares);
            }
        }
    }

    /// @notice start unlock timing for msg.sender
    function exit() external{
        //clear any previous withdraw queue and restart
        _clearWithdrawQueueGuarded(msg.sender);
        
        //claim all rewards now because reward0 will be excluded during
        //the withdraw sequence
        //will error if already in withdraw process
        getReward(msg.sender);

        //set withdraw time
        uint256 exitTime = block.timestamp + withdrawTime;
        withdrawQueue[msg.sender] = exitTime;

        emit Cooldown(msg.sender, balanceOf(msg.sender), exitTime);
    }

    /// @notice cancel exit timer for msg.sender
    function cancelExit() external{
        //canceling will remove claimable emissions
        //but will redistribute those claimable back into the pool
        //thus a portion will go back to msg.sender in accordance with its weight
        _clearWithdrawQueueGuarded(msg.sender);
        emit ExitCancel(msg.sender);
    }

    function _clearWithdrawQueueGuarded(address _account) internal nonReentrant{
        _clearWithdrawQueue(_account);
    }

    function _clearWithdrawQueue(address _account) internal {
        if(withdrawQueue[_account] != 0){
            //checkpoint rewards
            _checkpoint(_account);
            //get reward 0 info
            RewardType storage reward = rewards[0];
            address rewardToken = reward.reward_token;
            //note how much is claimable
            uint256 reward0 = claimable_reward[rewardToken][_account];
            //reset claimable
            claimable_reward[rewardToken][_account] = 0;
            //redistribute back to pool
            reward.reward_remaining -= reward0;

            withdrawQueue[_account] = 0; //flag as not waiting for withdraw
        }
    }

    function _checkWithdrawReady(address _account) internal view{
        uint256 exitTime = withdrawQueue[_account];
        require(exitTime > 0 && block.timestamp >= exitTime, "!withdraw time");
        require(block.timestamp <= exitTime + withdrawTimeLimit, "withdraw time over");
    }

    /// @notice burn shares and withdraw underlying assets
    /// @param _shares number of shares to redeem
    /// @param _receiver address to send underlying to
    /// @param _owner the account to redeem from (must equal msg.sender)
    /// @return assets amount of asset tokens received
    function redeem(uint256 _shares, address _receiver, address _owner) external nonReentrant returns (uint256 assets){
        require(msg.sender == _owner);

        _checkWithdrawReady(msg.sender);
        if (_shares > 0) {
            //clear queue will also checkpoint rewards
            _clearWithdrawQueue(msg.sender);
            
            assets = previewRedeem(_shares);
            require(assets != 0, "ZERO_ASSETS");
            _burn(msg.sender, _shares);
            IERC20(asset).safeTransfer(_receiver, assets);
            emit Withdraw(msg.sender, _receiver, msg.sender, _shares, assets);
        }
    }

    /// @notice withdraw underlying assets
    /// @param _amount amount of underlying assets to withdraw
    /// @param _receiver the receiving address
    /// @param _owner the account to redeem from (must equal msg.sender)
    /// @return shares amount of shares burned
    function withdraw(uint256 _amount, address _receiver, address _owner) external nonReentrant returns(uint256 shares){
        require(msg.sender == _owner);

        _checkWithdrawReady(msg.sender);
        if (_amount > 0) {
            //clear queue will also checkpoint rewards
            _clearWithdrawQueue(msg.sender);

            shares = previewWithdraw(_amount);
            _burn(msg.sender, shares);
            IERC20(asset).safeTransfer(_receiver, _amount);
            emit Withdraw(msg.sender, _receiver, msg.sender, shares, _amount);
        }
    }

    /// @notice get rewards for the given account
    /// @param _account the account to claim rewards for
    function getReward(address _account) public override{
        require(withdrawQueue[_account] == 0, "claim while queued");
        super.getReward(_account);
    }

    /// @notice get rewards for the given account
    /// @param _account the account to claim rewards for
    /// @param _forwardTo the address to send claimed rewards to
    function getReward(address _account, address _forwardTo) public override{
        require(withdrawQueue[_account] == 0, "claim while queued");
        super.getReward(_account,_forwardTo);
    }

    /// @notice check what rewards are claimable
    /// @param _account the account to query
    /// @dev not a view function
    function earned(address _account) public override returns(EarnedData[] memory claimable) {
        claimable = super.earned(_account);
        if(withdrawQueue[_account] > 0){
            claimable[0].amount = 0;
        }
    }

    function totalAssets() public view returns(uint256 assets){
        assets = IERC20(asset).balanceOf(address(this));
    }

    function convertToShares(uint256 _assets) public view returns (uint256 shares){
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            shares = _assets;
        } else {
            shares = _assets * _totalSupply / totalAssets();
        }
    }

    function convertToAssets(uint256 _shares) public view returns (uint256 assets){
        uint256 _totalSupply = totalSupply();
        if(_totalSupply > 0){
            assets = totalAssets() * _shares / _totalSupply;
        } else{
            assets = _shares;
        }
    }

    function convertToSharesRoundUp(uint256 _assets) internal view returns (uint256 shares){
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            shares = _assets;
        } else {
            uint256 _totalAssets = totalAssets();
            shares = _assets * _totalSupply / _totalAssets;
            if ( shares * _totalAssets / _totalSupply < _assets) {
                shares = shares + 1;
            }
        }
    }

    function convertToAssetsRoundUp(uint256 _shares) internal view returns (uint256 assets){
        uint256 _totalSupply = totalSupply();
        if(_totalSupply > 0){
            uint256 _totalAssets = totalAssets();
            assets = _totalAssets * _shares / _totalSupply;
            if ( assets * _totalSupply / _totalAssets < _shares) {
                assets = assets + 1;
            }
        }else{
            assets = _shares;
        }
    }

    function maxDeposit(address /*_receiver*/) external pure returns (uint256){
        return type(uint256).max;
    }
    function maxMint(address /*_receiver*/) external pure returns (uint256){
        return type(uint256).max;
    }
    function previewDeposit(uint256 _amount) public view returns (uint256){
        return convertToShares(_amount);
    }
    function previewMint(uint256 _shares) public view returns (uint256){
        return convertToAssetsRoundUp(_shares); //round up
    }
    function maxWithdraw(address _owner) external view returns (uint256){
        return convertToAssets(balanceOf(_owner));
    }
    function previewWithdraw(uint256 _amount) public view returns (uint256){
        return convertToSharesRoundUp(_amount); //round up
    }
    function maxRedeem(address _owner) external view returns (uint256){
        return balanceOf(_owner);
    }
    function previewRedeem(uint256 _shares) public view returns (uint256){
        return convertToAssets(_shares);
    }

}