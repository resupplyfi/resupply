// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

interface IConvexStaking {
    function poolInfo(uint256 _pid) external view returns(
        address lptoken,
        address token,
        address gauge,
        address crvRewards,
        address stash,
        bool shutdown
    );
    function deposit(uint256 _pid, uint256 _amount, bool _stake) external returns(bool);
    function depositAll(uint256 _pid, bool _stake) external returns(bool);
    function withdrawAndUnwrap(uint256 amount, bool claim) external returns(bool);
    function withdrawAllAndUnwrap(bool claim) external;
    function getReward() external returns(bool);
    function getReward(address _account, bool _claimExtras) external returns(bool);
    function totalSupply() external view returns (uint256);
    function extraRewardsLength() external view returns (uint256);
    function extraRewards(uint256 _rid) external view returns (address _rewardContract);
    function rewardToken() external view returns (address _rewardToken);
    function token() external view returns (address _token);
    function balanceOf(address account) external view returns (uint256);
}
