// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { IGovStaker } from "src/interfaces/IGovStaker.sol";
import { CoreOwnable } from "src/dependencies/CoreOwnable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract VestClaimCallback is CoreOwnable {
    using SafeERC20 for IERC20;

    IGovStaker public immutable govStaker;
    address public immutable vestManager;
    IERC20 public immutable token;

    event RecoveredERC20(address indexed token, address indexed recipient, uint256 amount);

    constructor(address _core, address _govStaker, address _vestManager) CoreOwnable(_core) {
        govStaker = IGovStaker(_govStaker);
        vestManager = _vestManager;
        token = IERC20(govStaker.stakeToken());
        token.approve(_govStaker, type(uint256).max);
    }

    function onClaim(
        address account,
        address recipient,
        uint256 amount
    ) external returns (bool success) {
        require(msg.sender == vestManager, "!authorized");
        govStaker.stake(recipient, amount);
        return true;
    }

    function recoverERC20(address _token, address _recipient, uint256 _amount) external onlyOwner {
        IERC20(_token).safeTransfer(_recipient, _amount);
        emit RecoveredERC20(_token, _recipient, _amount);
    }
}