// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Setup } from "test/e2e/Setup.sol";
import { Prisma, Mainnet } from "src/Constants.sol";
import { PrismaFeeForwarder } from "src/dao/operators/PrismaFeeForwarder.sol";
import { IPrismaVoterProxy } from "src/interfaces/prisma/IPrismaVoterProxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract PrismaFeeForwarderTest is Setup {
    PrismaFeeForwarder public forwarder;

    function setUp() public override {
        super.setUp();
        forwarder = new PrismaFeeForwarder(address(core));

        vm.prank(address(voter));
        core.execute(
            Prisma.VOTER_PROXY,
            abi.encodeWithSelector(IPrismaVoterProxy.setDepositManager.selector, address(forwarder))
        );

        assertEq(IPrismaVoterProxy(Prisma.VOTER_PROXY).depositManager(), address(forwarder));
    }

    function test_ClaimFeesMultipleEpochs() public {
        address receiver = forwarder.receiver();
        uint256 amount = 1_000e18;
        IERC20 scrvusd = IERC20(Mainnet.SCRVUSD_ERC20);

        deal(Mainnet.CRVUSD_ERC20, Prisma.VOTER_PROXY, amount);
        uint256 receiverBefore = scrvusd.balanceOf(receiver);
        uint256 claimed = forwarder.claimFees();

        assertGt(claimed, 0, "claim 1 should be non-zero");
        assertGt(scrvusd.balanceOf(receiver), receiverBefore);
        assertEq(crvusdToken.balanceOf(Prisma.VOTER_PROXY), 0);

        skip(epochLength * 3);

        deal(Mainnet.CRVUSD_ERC20, Prisma.VOTER_PROXY, amount);
        receiverBefore = scrvusd.balanceOf(receiver);
        claimed = forwarder.claimFees();

        assertGt(claimed, 0, "claim 2 should be non-zero");
        assertGt(scrvusd.balanceOf(receiver), receiverBefore);
        assertEq(crvusdToken.balanceOf(Prisma.VOTER_PROXY), 0);

    }
}
