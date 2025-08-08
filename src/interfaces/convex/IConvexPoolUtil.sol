// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IConvexPoolUtil {
    function rewardRates(uint256 _pid) external view returns (address[] memory tokens, uint256[] memory rates);
}
