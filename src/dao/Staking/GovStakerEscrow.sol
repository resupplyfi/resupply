// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.22;
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

contract GovStakerEscrow {
    address immutable GOV_STAKER;
    IERC20 immutable TOKEN;

    constructor(address govStaker, address token) {
        GOV_STAKER = govStaker;
        TOKEN = IERC20(token);
    }

    modifier onlyStaker() {
        require(msg.sender == GOV_STAKER, '!Staker');
        _;
    }

    function withdraw(address to, uint256 amount) external onlyStaker {
        TOKEN.transfer(to, amount);
    }
}
