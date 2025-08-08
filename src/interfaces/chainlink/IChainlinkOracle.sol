// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IChainlinkOracle {

    function latestAnswer() external view returns (int256 answer);
    function latestRound() external view returns (int256 answer);
    function getRoundData(uint80 _roundId) external view returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    );
    function latestRoundData() external view returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    );

}