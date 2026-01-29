// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { CoreOwnable } from "src/dependencies/CoreOwnable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IPrismaVoterProxy } from "src/interfaces/prisma/IPrismaVoterProxy.sol";
import { IERC4626 } from "src/interfaces/IERC4626.sol";

interface IPrismaFeeDistributor {
    function claim(address recipient) external returns (uint256);
}

contract PrismaFeeForwarder is CoreOwnable {
    using SafeERC20 for IERC20;

    address public constant PRISMA_VOTER = 0x490b8C6007fFa5d3728A49c2ee199e51f05D2F7e;
    address public constant FEE_DISTRIBUTOR = 0xD16d5eC345Dd86Fb63C6a9C43c517210F1027914;
    address public constant CRVUSD = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
    address public constant SCRVUSD = 0x0655977FEb2f289A4aB78af67BAB0d17aAb84367;

    address public receiver = 0x4444444455bF42de586A88426E5412971eA48324;

    event ReceiverSet(address indexed receiver);

    constructor(address _core) CoreOwnable(_core) {
        IERC20(CRVUSD).forceApprove(SCRVUSD, type(uint256).max);
    }

    function setReceiver(address _receiver) external onlyOwner {
        require(_receiver != address(0));
        receiver = _receiver;
        emit ReceiverSet(_receiver);
    }

    function claimFees() external returns (uint256 amount) {
        IPrismaFeeDistributor(FEE_DISTRIBUTOR).claim(PRISMA_VOTER);

        amount = IERC20(CRVUSD).balanceOf(PRISMA_VOTER);
        if (amount == 0) return 0;
        IPrismaVoterProxy.TokenBalance[] memory balances = new IPrismaVoterProxy.TokenBalance[](1);
        balances[0] = IPrismaVoterProxy.TokenBalance({ token: IERC20(CRVUSD), amount: amount });

        IPrismaVoterProxy(PRISMA_VOTER).transferTokens(address(this), balances);

        IERC4626(SCRVUSD).deposit(amount, receiver);
    }
}
