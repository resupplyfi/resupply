// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { BaseProposalTest } from "test/integration/proposals/BaseProposalTest.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IERC4626 } from "src/interfaces/IERC4626.sol";
import { UpdateIRCalc } from "script/proposals/UpdateIRCalc.s.sol";
import { ResupplyPairDeployer } from "src/protocol/ResupplyPairDeployer.sol";

contract UpdateIRCalcTest is BaseProposalTest {
    UpdateIRCalc public script;
    address public newRateCalculator;
    ResupplyPairDeployer.ConfigData public oldDefaultConfig;
    uint128[] public oldLastShares;

    function setUp() public override {
        super.setUp();
        script = new UpdateIRCalc();
        newRateCalculator = script.NEW_RATE_CALCULATOR();
        oldDefaultConfig = ResupplyPairDeployer(address(deployer)).defaultConfigData();

        oldLastShares = new uint128[](pairs.length);
        for (uint256 i = 0; i < pairs.length; i++) {
            (,, oldLastShares[i]) = IResupplyPair(pairs[i]).currentRateInfo();
        }

        IVoter.Action[] memory actions = script.buildProposalCalldata();
        uint256 proposalId = createProposal(actions);
        simulatePassingVote(proposalId);
        executeProposal(proposalId);
    }

    function test_ProposalActionCountMatchesPairs() public {
        IVoter.Action[] memory actions = script.buildProposalCalldata();
        assertEq(actions.length, pairs.length + 1, "unexpected action count");
    }

    function test_DefaultConfigUpdated() public view {
        ResupplyPairDeployer.ConfigData memory newConfig = ResupplyPairDeployer(address(deployer)).defaultConfigData();
        assertEq(newConfig.oracle, oldDefaultConfig.oracle, "oracle changed");
        assertEq(newConfig.rateCalculator, newRateCalculator, "default rate calculator not updated");
        assertEq(newConfig.maxLTV, oldDefaultConfig.maxLTV, "maxLTV changed");
        assertEq(newConfig.initialBorrowLimit, oldDefaultConfig.initialBorrowLimit, "borrow limit changed");
        assertEq(newConfig.liquidationFee, oldDefaultConfig.liquidationFee, "liquidation fee changed");
        assertEq(newConfig.mintFee, oldDefaultConfig.mintFee, "mint fee changed");
        assertEq(newConfig.protocolRedemptionFee, oldDefaultConfig.protocolRedemptionFee, "protocol fee changed");
    }

    function test_RateCalculatorsUpdated() public view {
        for (uint256 i = 0; i < pairs.length; i++) {
            IResupplyPair pair = IResupplyPair(pairs[i]);
            assertEq(pair.rateCalculator(), newRateCalculator, "rate calculator not updated");
            (,, uint128 lastShares) = pair.currentRateInfo();
            assertEq(lastShares, oldLastShares[i], "last shares changed during upgrade");
        }
    }

    function test_NewCalculatorRefreshesLastSharesOnNextAccrual() public {
        IResupplyPair pair = IResupplyPair(pairs[0]);
        skip(1);
        pair.addInterest(false);

        (,, uint128 lastShares) = pair.currentRateInfo();
        assertEq(pair.rateCalculator(), newRateCalculator, "rate calculator not updated");
        assertEq(lastShares, IERC4626(pair.collateral()).convertToShares(1e18), "last shares mismatch");
        assertGt(lastShares, 0, "last shares zero");
    }

    function test_NewCalculatorRefreshesLastSharesOnNextAccrualForZeroBaseline() public {
        for (uint256 i = 0; i < pairs.length; i++) {
            IResupplyPair pair = IResupplyPair(pairs[i]);
            (,, uint128 lastShares) = pair.currentRateInfo();
            if (lastShares != 0) continue;

            skip(1);
            pair.addInterest(false);

            (,, lastShares) = pair.currentRateInfo();
            assertEq(lastShares, IERC4626(pair.collateral()).convertToShares(1e18), "last shares mismatch");
            assertGt(lastShares, 0, "last shares zero");
            return;
        }

        vm.skip(true);
    }
}
