// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol, DeploymentConfig } from "src/Constants.sol";
import { BaseProposalTest } from "test/integration/proposals/BaseProposalTest.sol";
import { PermissionHelper } from "script/utils/PermissionHelper.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { SecurityGuardrailsBuilder } from "script/proposals/data/SecurityGuardrailsBuilder.sol";
import { IResupplyPairDeployer } from "src/interfaces/IResupplyPairDeployer.sol";
import { BytesLib } from "solidity-bytes-utils/contracts/BytesLib.sol";
import { ResupplyPair } from "src/protocol/ResupplyPair.sol";
import { ResupplyPairDeployer } from "src/protocol/ResupplyPairDeployer.sol";
import { DeployInfo } from "script/actions/DeployFixes.s.sol";

contract SecurityGuardrailsTest is BaseProposalTest {

    function setUp() public override {
        super.setUp();
        _deployPairDeployer();
        IVoter.Action[] memory actions = SecurityGuardrailsBuilder.buildProposalCalldata();
        uint256 proposalId = createProposal(actions);
        simulatePassingVote(proposalId);
        executeProposal(proposalId);
    }
    
    function test_DeployerCodeSet() public {
        bytes memory code = IResupplyPairDeployer(Protocol.PAIR_DEPLOYER_V1).contractAddress1().code;
        assertLt(code.length, 2);
        IResupplyPairDeployer deployer = IResupplyPairDeployer(Protocol.PAIR_DEPLOYER_V2);
        assertGt(deployer.contractAddress1().code.length, 2);
        assertGt(deployer.contractAddress2().code.length, 2);
    }

    function test_OracleSetToZero() public {
        (address oracle, ,) = IResupplyPair(Protocol.PAIR_CURVELEND_WSTUR_CRVUSD).exchangeRateInfo();
        assertEq(oracle, address(0));
    }

    function test_PermissionsSet() public {
        assertTrue(PermissionHelper.isEnabled(Protocol.BORROW_LIMIT_CONTROLLER, address(0), IResupplyPair.setBorrowLimit.selector));
        assertTrue(PermissionHelper.isEnabled(Protocol.PAIR_ADDER, Protocol.REGISTRY, IResupplyRegistry.addPair.selector));
    }

    function test_OraclesUpgraded() public {
        address[] memory pairs = registry.getAllPairAddresses();
        uint256 numPairs = pairs.length;
        // Oracle updates for all pairs
        IVoter.Action[] memory oracleActions = new IVoter.Action[](numPairs);
        for (uint256 i = 0; i < numPairs; i++) {
            address pair = pairs[i];
            (address oracle, ,) = IResupplyPair(pairs[i]).exchangeRateInfo();
            if (pair == Protocol.PAIR_CURVELEND_WSTUR_CRVUSD) {
                assertEq(oracle, address(0));
            } else {
                assertEq(oracle, Protocol.BASIC_VAULT_ORACLE);
                assertNotEq(oracle, Protocol.BASIC_VAULT_ORACLE_OLD);
            }
        }
    }

    function _deployPairDeployer() public {
        (address[] memory previouslyDeployedPairs, ResupplyPairDeployer.DeployInfo[] memory previouslyDeployedPairsInfo) = DeployInfo.getDeployInfo();
        ResupplyPairDeployer.ConfigData memory configData = ResupplyPairDeployer.ConfigData({
            oracle: Protocol.BASIC_VAULT_ORACLE,
            rateCalculator: Protocol.INTEREST_RATE_CALCULATOR_V2,
            maxLTV: DeploymentConfig.DEFAULT_MAX_LTV,
            initialBorrowLimit: DeploymentConfig.DEFAULT_BORROW_LIMIT,
            liquidationFee: DeploymentConfig.DEFAULT_LIQ_FEE,
            mintFee: DeploymentConfig.DEFAULT_MINT_FEE,
            protocolRedemptionFee: DeploymentConfig.DEFAULT_PROTOCOL_REDEMPTION_FEE
        });
        ResupplyPairDeployer deployer = new ResupplyPairDeployer(
            Protocol.CORE,
            Protocol.REGISTRY,
            Protocol.GOV_TOKEN,
            Protocol.DEPLOYER,
            configData,
            previouslyDeployedPairs,
            previouslyDeployedPairsInfo
        );
        vm.etch(Protocol.PAIR_DEPLOYER_V2, address(deployer).code);
    }
}