// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IGovStakerEscrow {
  function withdraw(address to, uint256 amount) external;
}
