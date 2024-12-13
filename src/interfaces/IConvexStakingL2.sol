// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

interface IConvexStakingL2 {
    function poolInfo(uint256 _pid) external view returns(
        address lptoken,
        address gauge,
        address rewards,
        bool shutdown,
        address factory
    );
    function deposit(uint256 _pid, uint256 _amount) external returns(bool);
    function depositAll(uint256 _pid) external returns(bool);
    function withdraw(uint256 amount, bool claim) external returns(bool);
    function getReward(address _account) external returns(bool);
    function getReward(address _account, address _forwardTo) external returns(bool);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
}
