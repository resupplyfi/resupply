// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

contract GovStakerEscrow {
    address immutable staker;
    IERC20 immutable token;

    constructor(address _staker, address _token) {
        staker = _staker;
        token = IERC20(_token);
    }

    modifier onlyStaker() {
        require(msg.sender == staker, "!Staker");
        _;
    }

    function withdraw(address to, uint256 amount) external onlyStaker {
        token.transfer(to, amount);
    }
}