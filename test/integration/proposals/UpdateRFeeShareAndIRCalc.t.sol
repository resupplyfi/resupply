// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { BaseProposalTest } from "test/integration/proposals/BaseProposalTest.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { Protocol } from "src/Constants.sol";
import { UpdateRFeeShareAndIRCalc } from "script/proposals/UpdateRFeeShareAndIRCalc.s.sol";
import { ResupplyPairDeployer } from "src/protocol/ResupplyPairDeployer.sol";

contract UpdateRFeeShareAndIRCalcTest is BaseProposalTest {
    uint256 public constant PROP_ID = 15;
    UpdateRFeeShareAndIRCalc public script;
    address public samplePair;
    address public oldRateCalculator;
    uint256 public oldProtocolRedemptionFee;
    ResupplyPairDeployer.ConfigData public oldDefaultConfig;

    function setUp() public override {
        super.setUp();
        if (isProposalProcessed(PROP_ID)) return;
        testPair = IResupplyPair(pairs[5]);
        oldRateCalculator = IResupplyPair(address(testPair)).rateCalculator();
        oldProtocolRedemptionFee = IResupplyPair(address(testPair)).protocolRedemptionFee();
        oldDefaultConfig = ResupplyPairDeployer(address(deployer)).defaultConfigData();
        script = new UpdateRFeeShareAndIRCalc();
        IVoter.Action[] memory actions = script.buildProposalCalldata();
        uint256 proposalId = createProposal(actions);
        simulatePassingVote(proposalId);
        executeProposal(proposalId);
    }

    function test_RateCalculatorsUpdated() public {
        if (isProposalProcessed(PROP_ID)) return;
        for (uint256 i = 0; i < pairs.length; i++) {
            assertEq(
                address(IResupplyPair(pairs[i]).rateCalculator()),
                Protocol.INTEREST_RATE_CALCULATOR_V2_1,
                "rate calculator not updated"
            );
        }
        assertNotEq(
            oldRateCalculator,
            Protocol.INTEREST_RATE_CALCULATOR_V2_1,
            "old calculator matches new"
        );
    }

    function test_RedemptionFeeUpdated() public {
        if (isProposalProcessed(PROP_ID)) return;
        for (uint256 i = 0; i < pairs.length; i++) {
            assertEq(
                IResupplyPair(pairs[i]).protocolRedemptionFee(),
                script.newProtocolRedemptionFee(),
                "protocol redemption fee not updated"
            );
        }
        assertNotEq(oldProtocolRedemptionFee, 0.05e18, "old fee matches new");
    }

    function test_DefaultConfigUpdated() public {
        if (isProposalProcessed(PROP_ID)) return;
        ResupplyPairDeployer.ConfigData memory newConfig = ResupplyPairDeployer(address(deployer)).defaultConfigData();
        assertEq(newConfig.oracle, oldDefaultConfig.oracle, "oracle changed");
        assertEq(newConfig.maxLTV, oldDefaultConfig.maxLTV, "maxLTV changed");
        assertEq(newConfig.initialBorrowLimit, oldDefaultConfig.initialBorrowLimit, "borrow limit changed");
        assertEq(newConfig.liquidationFee, oldDefaultConfig.liquidationFee, "liquidation fee changed");
        assertEq(newConfig.mintFee, oldDefaultConfig.mintFee, "mint fee changed");
        assertEq(newConfig.protocolRedemptionFee, oldDefaultConfig.protocolRedemptionFee, "protocol fee changed");
        assertEq(newConfig.rateCalculator, Protocol.INTEREST_RATE_CALCULATOR_V2_1, "rate calculator not updated");
        assertNotEq(oldDefaultConfig.rateCalculator, newConfig.rateCalculator, "rate calculator unchanged");
    }

    function test_UtilitiesRegistryUpdated() public {
        address utilities = registry.getAddress("UTILITIES");
        assertEq(utilities, Protocol.UTILITIES, "utilities not updated");
    }

}
