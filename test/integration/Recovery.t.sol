// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "lib/forge-std/src/Test.sol";
import { console } from "lib/forge-std/src/console.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { BadDebtPayer } from "src/dao/misc/BadDebtPayer.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { Setup } from "test/integration/Setup.sol";
import { Protocol } from "src/Constants.sol";
import { Voter } from "src/dao/Voter.sol";
import { IVoterDeprecated } from "src/interfaces/IVoterDeprecated.sol";
import { IGovStaker } from "src/interfaces/IGovStaker.sol";

contract RecoveryTest is Setup {
    uint256 public constant AMOUNT = 6_000_000e18;
    address public constant BORROWER = 0x151aA63dbb7C605E7b0a173Ab7375e1450E79238;
    IResupplyPair public constant PAIR = IResupplyPair(0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6);
    BadDebtPayer public constant badDebtPayer = BadDebtPayer(0x024b682c064c287ea5ca7b6CB2c038d42f34EA0D);
    address public constant VOTER = 0x11111111063874cE8dC6232cb5C1C849359476E6;
    IVoterDeprecated public _voter;

    function setUp() public override {
        super.setUp();
        _voter = IVoterDeprecated(VOTER);
        vm.startPrank(address(core));
        core.setVoter(VOTER);
        registry.setAddress("VOTER", VOTER);
        vm.stopPrank();
    }

    function test_RecoverySimple() public {
        address liquidationHandler = registry.liquidationHandler();
        vm.startPrank(address(core));
        registry.setLiquidationHandler(address(core));
        insurancePool.burnAssets(AMOUNT);
        stablecoin.mint(address(core), AMOUNT);
        stablecoin.approve(address(badDebtPayer), AMOUNT);
        badDebtPayer.payBadDebt(AMOUNT);
        registry.setLiquidationHandler(liquidationHandler);
        vm.stopPrank();
    }

    function test_RecoveryViaGovernance() public {
        uint256 startingSupply = stablecoin.totalSupply();
        (uint256 totalBorrow, uint256 totalShares) = PAIR.totalBorrow();
        address currentLiquidationHandler = registry.liquidationHandler();
        
        // Action 1: Set liquidation handler to core
        bytes memory setLiquidationHandlerCalldata = abi.encodeWithSignature(
            "setLiquidationHandler(address)",
            address(core)
        );
        // Action 2: Burn assets from insurance pool
        bytes memory burnAssetsCalldata = abi.encodeWithSignature(
            "burnAssets(uint256)",
            AMOUNT
        );
        // Action 3: Mint stablecoin to core
        bytes memory mintCalldata = abi.encodeWithSignature(
            "mint(address,uint256)",
            address(core),
            AMOUNT
        );
        // Action 4: Approve BadDebtPayer to spend stablecoin
        bytes memory approveCalldata = abi.encodeWithSignature(
            "approve(address,uint256)",
            address(badDebtPayer),
            AMOUNT
        );
        // Action 5: Call payBadDebt on BadDebtPayer
        bytes memory payBadDebtCalldata = abi.encodeWithSignature(
            "payBadDebt(uint256)",
            AMOUNT
        );        
        // Action 6: Set liquidation handler back to original
        bytes memory restoreLiquidationHandlerCalldata = abi.encodeWithSignature(
            "setLiquidationHandler(address)",
            currentLiquidationHandler
        );
        // Action 7: Reset IP withdraw timers
        bytes memory resetIpWithdrawTimersCalldata = abi.encodeWithSignature(
            "setWithdrawTimers(uint256,uint256)",
            7 days + 1 seconds,
            3 days + 1 seconds
        );
        // Action 8: Set voter voting period to 7 days
        bytes memory setVoterTimeCalldata = abi.encodeWithSignature(
            "setVotingPeriod(uint256)",
            7 days
        );
        // Action 9: Set voter execution delay to 1 day
        bytes memory setExecutionDelayCalldata = abi.encodeWithSignature(
            "setExecutionDelay(uint256)",
            1 days
        );

        IVoterDeprecated.Action[] memory actions = new IVoterDeprecated.Action[](9);
        actions[0] = IVoterDeprecated.Action({
            target: address(registry),
            data: setLiquidationHandlerCalldata
        });
        actions[1] = IVoterDeprecated.Action({
            target: address(insurancePool),
            data: burnAssetsCalldata
        });
        actions[2] = IVoterDeprecated.Action({
            target: address(stablecoin),
            data: mintCalldata
        });
        actions[3] = IVoterDeprecated.Action({
            target: address(stablecoin),
            data: approveCalldata
        });
        actions[4] = IVoterDeprecated.Action({
            target: address(badDebtPayer),
            data: payBadDebtCalldata
        });
        actions[5] = IVoterDeprecated.Action({
            target: address(registry),
            data: restoreLiquidationHandlerCalldata
        });
        actions[6] = IVoterDeprecated.Action({
            target: address(insurancePool),
            data: resetIpWithdrawTimersCalldata
        });
        actions[7] = IVoterDeprecated.Action({
            target: address(voter),
            data: setVoterTimeCalldata
        });
        actions[8] = IVoterDeprecated.Action({
            target: address(voter),
            data: setExecutionDelayCalldata
        });

        (uint256 initialTotalBorrow, ) = PAIR.totalBorrow();
        uint256 initialCoreBalance = IERC20(address(stablecoin)).balanceOf(address(core));
        
        // Create the governance proposal
        vm.prank(Protocol.PERMA_STAKER_CONVEX);
        uint256 proposalId = _voter.createNewProposal(
            Protocol.PERMA_STAKER_CONVEX,
            actions,
            "Pay bad debt through governance"
        );
        
        console.log("Created proposal ID:", proposalId);
        
        // Simulate votes
        vm.prank(Protocol.PERMA_STAKER_CONVEX);
        _voter.voteForProposal(Protocol.PERMA_STAKER_CONVEX, proposalId);
        vm.prank(Protocol.PERMA_STAKER_YEARN);
        _voter.voteForProposal(Protocol.PERMA_STAKER_YEARN, proposalId);
        
        skip(3.5 days);
        assertTrue(_voter.canExecute(proposalId), "Proposal should be executable");
        _voter.executeProposal(proposalId);
        
        // Checks
        (uint256 finalTotalBorrow, ) = PAIR.totalBorrow();
        uint256 finalCoreBalance = IERC20(address(stablecoin)).balanceOf(address(core));
        console.log("Governance proposal executed successfully");
        console.log("Borrow reduction:", initialTotalBorrow - finalTotalBorrow);
        console.log("reUSD supply reduction:", startingSupply - stablecoin.totalSupply());
        console.log("Final total borrow:", finalTotalBorrow);
        console.log("Final core balance:", finalCoreBalance);
        
        assertEq(stablecoin.totalSupply(), startingSupply - AMOUNT, "Stablecoin supply should be reduced by burn");
        assertLt(finalTotalBorrow, initialTotalBorrow, "Total borrow should have decreased");
        assertEq(registry.liquidationHandler(), currentLiquidationHandler, "Liquidation handler should be restored");
        assertEq(insurancePool.withdrawTime(), 7 days + 1 seconds, "Withdraw time should be set to 7 days");
        assertEq(insurancePool.withdrawTimeLimit(), 3 days + 1 seconds, "Withdraw time limit should be set to 3 days");
        assertEq(_voter.votingPeriod(), 7 days, "Voting period should be set to 7 days");
        assertEq(_voter.executionDelay(), 1 days, "Execution delay should be set to 1 day");
    }
}