// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { BaseProposalTest } from "test/integration/proposals/BaseProposalTest.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { Protocol } from "src/Constants.sol";
import { UpdateRFeeShareAndIRCalc } from "script/proposals/UpdateRFeeShareAndIRCalc.s.sol";
import { ResupplyPairDeployer } from "src/protocol/ResupplyPairDeployer.sol";
import { Utilities } from "src/protocol/Utilities.sol";
import { console } from "lib/forge-std/src/console.sol";

contract UpdateRFeeShareAndIRCalcTest is BaseProposalTest {
    uint256 public constant PROP_ID = 15;
    UpdateRFeeShareAndIRCalc public script;
    address public samplePair;
    address public oldRateCalculator;
    uint256 public oldProtocolRedemptionFee;
    ResupplyPairDeployer.ConfigData public oldDefaultConfig;
    uint256[] public preRates;
    uint256[] public postRates;

    function setUp() public override {
        super.setUp();
        if (isProposalProcessed(PROP_ID)) vm.skip(true);
        testPair = IResupplyPair(pairs[5]);
        oldRateCalculator = IResupplyPair(address(testPair)).rateCalculator();
        oldProtocolRedemptionFee = IResupplyPair(address(testPair)).protocolRedemptionFee();
        oldDefaultConfig = ResupplyPairDeployer(address(deployer)).defaultConfigData();
        script = new UpdateRFeeShareAndIRCalc();
        IVoter.Action[] memory actions = script.buildProposalCalldata();
        address oldUtilities = registry.getAddress("UTILITIES");
        preRates = _snapshotRates(oldUtilities);
        uint256 proposalId = createProposal(actions);
        simulatePassingVote(proposalId);
        executeProposal(proposalId);
        address newUtilities = registry.getAddress("UTILITIES");
        postRates = _snapshotRates(newUtilities);
    }

    function test_RateCalculatorsUpdated() public {
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

    function test_LogPairRates() public {
        if (preRates.length == 0 || postRates.length == 0) {
            address utilities = registry.getAddress("UTILITIES");
            preRates = _snapshotRates(utilities);
            postRates = _snapshotRates(utilities);
        }
        _logRateChanges();
    }

    function _snapshotRates(address utilitiesAddr) internal view returns (uint256[] memory rates) {
        Utilities utilities = Utilities(utilitiesAddr);
        uint256 length = pairs.length;
        rates = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            rates[i] = utilities.getPairInterestRate(pairs[i]);
        }
    }

    function _logRateChanges() internal {
        uint256 length = pairs.length;
        uint256 maxNameLen = 0;
        for (uint256 i = 0; i < length; i++) {
            uint256 nameLen = bytes(_cleanPairName(IResupplyPair(pairs[i]).name())).length;
            if (nameLen > maxNameLen) maxNameLen = nameLen;
        }
        for (uint256 i = 0; i < length; i++) {
            uint256 preApr = preRates[i] * 365 days;
            uint256 postApr = postRates[i] * 365 days;
            string memory pairName = _padRight(_cleanPairName(IResupplyPair(pairs[i]).name()), maxNameLen);
            console.log("%s | %18e -> %18e", pairName, preApr, postApr);
        }
    }

    function _padRight(string memory value, uint256 totalLen) internal pure returns (string memory) {
        bytes memory data = bytes(value);
        if (data.length >= totalLen) return value;
        bytes memory out = new bytes(totalLen);
        for (uint256 i = 0; i < data.length; i++) out[i] = data[i];
        for (uint256 i = data.length; i < totalLen; i++) out[i] = 0x20;
        return string(out);
    }

}
