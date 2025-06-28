// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IResupplyPair} from "src/interfaces/IResupplyPair.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BadDebtPayer {
    IResupplyPair public constant pair = IResupplyPair(0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6);
    IERC20 public constant token = IERC20(0x57aB1E0003F623289CD798B1824Be09a793e4Bec);
    address public constant BORROWER = 0x151aA63dbb7C605E7b0a173Ab7375e1450E79238;
    address public constant core = 0xc07e000044F95655c11fda4cD37F70A94d7e0a7d;

    event BadDebtPaid(uint256 amount, uint256 shares);

    constructor() {
        token.approve(address(pair), type(uint256).max);
    }

    function payBadDebt(uint256 _amount) external {
        token.transferFrom(msg.sender, address(this), _amount);
        (uint256 totalBorrow, uint256 totalShares) = pair.totalBorrow();
        if (_amount > totalBorrow) {
            uint256 overflow = _amount - totalBorrow;
            _amount -= overflow;
            token.transfer(core, overflow);
        }
        if (_amount > 0) {
            uint256 sharesToRepay = pair.toBorrowShares(_amount, false, false);
            pair.repay(sharesToRepay, BORROWER);
            emit BadDebtPaid(_amount, sharesToRepay);
        }
    }

    function recoverERC20(address _token) external {
        IERC20(_token).transfer(core, IERC20(_token).balanceOf(address(this)));
    }
}