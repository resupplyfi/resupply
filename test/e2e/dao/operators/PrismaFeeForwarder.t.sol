// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Setup } from "test/e2e/Setup.sol";
import { Prisma, Mainnet } from "src/Constants.sol";
import { PrismaFeeForwarder } from "src/dao/operators/PrismaFeeForwarder.sol";
import { IPrismaVoterProxy } from "src/interfaces/prisma/IPrismaVoterProxy.sol";

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

        deal(Mainnet.CRVUSD_ERC20, Prisma.VOTER_PROXY, amount);
        uint256 receiverBefore = crvusdToken.balanceOf(receiver);
        uint256 claimed = forwarder.claimFees();

        assertGt(claimed, 0, "claim 1 should be non-zero");
        assertEq(crvusdToken.balanceOf(receiver), receiverBefore + claimed);
        assertEq(crvusdToken.balanceOf(Prisma.VOTER_PROXY), 0);

        skip(epochLength * 3);

        deal(Mainnet.CRVUSD_ERC20, Prisma.VOTER_PROXY, amount);
        receiverBefore = crvusdToken.balanceOf(receiver);
        claimed = forwarder.claimFees();

        assertGt(claimed, 0, "claim 2 should be non-zero");
        assertEq(crvusdToken.balanceOf(receiver), receiverBefore + claimed);
        assertEq(crvusdToken.balanceOf(Prisma.VOTER_PROXY), 0);

        skip(epochLength);

        receiverBefore = crvusdToken.balanceOf(receiver);
        claimed = forwarder.claimFees();
        // assertEq(claimed, 0, "should have claimed zero");
        assertEq(crvusdToken.balanceOf(receiver), receiverBefore + claimed, "receiver gain != claim");
        assertEq(crvusdToken.balanceOf(Prisma.VOTER_PROXY), 0);
    }
}