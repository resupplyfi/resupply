// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "lib/forge-std/src/Test.sol";
import { console } from "lib/forge-std/src/console.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { BadDebtPayer } from "src/dao/misc/BadDebtPayer.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { Setup } from "test/integration/Setup.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { Protocol } from "src/Constants.sol";
import { Voter } from "src/dao/Voter.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { IGovStaker } from "src/interfaces/IGovStaker.sol";

contract RecoveryTest is Setup {
    BadDebtPayer public badDebtPayer;
    uint256 public constant AMOUNT = 6_000_000e18;
    address public constant BORROWER = 0x151aA63dbb7C605E7b0a173Ab7375e1450E79238;
    IResupplyPair public constant PAIR = IResupplyPair(0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6);

    function setUp() public override {
        super.setUp();
        badDebtPayer = new BadDebtPayer();
        voter = IVoter(address(new Voter(address(core), IGovStaker(address(staker)), 100, 3000)));
        vm.startPrank(address(core));
        core.setVoter(address(voter));
        registry.setAddress("VOTER", address(voter));
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
        
        IVoter.Action[] memory actions = new IVoter.Action[](6);
        actions[0] = IVoter.Action({
            target: address(registry),
            data: setLiquidationHandlerCalldata
        });
        actions[1] = IVoter.Action({
            target: address(insurancePool),
            data: burnAssetsCalldata
        });
        actions[2] = IVoter.Action({
            target: address(stablecoin),
            data: mintCalldata
        });
        actions[3] = IVoter.Action({
            target: address(stablecoin),
            data: approveCalldata
        });
        actions[4] = IVoter.Action({
            target: address(badDebtPayer),
            data: payBadDebtCalldata
        });
        actions[5] = IVoter.Action({
            target: address(registry),
            data: restoreLiquidationHandlerCalldata
        });
        
        // Record initial state
        (uint256 initialTotalBorrow, ) = PAIR.totalBorrow();
        uint256 initialCoreBalance = IERC20(address(stablecoin)).balanceOf(address(core));
        
        console.log("Initial core balance:", initialCoreBalance);
        
        // Create the governance proposal
        vm.prank(Protocol.PERMA_STAKER_CONVEX);
        uint256 proposalId = voter.createNewProposal(
            Protocol.PERMA_STAKER_CONVEX,
            actions,
            "Pay bad debt through governance"
        );
        
        console.log("Created proposal ID:", proposalId);
        
        // Simulate votes
        vm.prank(Protocol.PERMA_STAKER_CONVEX);
        voter.voteForProposal(Protocol.PERMA_STAKER_CONVEX, proposalId);
        vm.prank(Protocol.PERMA_STAKER_YEARN);
        voter.voteForProposal(Protocol.PERMA_STAKER_YEARN, proposalId);
        
        skip(voter.votingPeriod() + voter.executionDelay());
        assertTrue(voter.canExecute(proposalId), "Proposal should be executable");
        
        // Execute the proposal
        voter.executeProposal(proposalId);
        

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
        (,,,,,, bool processed,, ) = voter.getProposalData(proposalId);
        assertTrue(processed, "Proposal should be marked as processed");
    }
}