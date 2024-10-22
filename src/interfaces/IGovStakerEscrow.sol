// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

interface IGovStakerEscrow {
  function withdraw(address to, uint256 amount) external;
}
