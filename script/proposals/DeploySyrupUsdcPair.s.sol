// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol } from "src/Constants.sol";
import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { CurveLendV2PairDeployer } from "script/actions/dependencies/CurveLendV2PairDeployer.sol";
import { IBorrowLimitController } from "src/interfaces/IBorrowLimitController.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { ResupplyPairDeployer } from "src/protocol/ResupplyPairDeployer.sol";
import { console } from "lib/forge-std/src/console.sol";

contract DeploySyrupUsdcPair is BaseAction {
    IVoter public constant voter = IVoter(Protocol.VOTER);

    string public constant DESCRIPTION =
        "Deploy the CurveLendV2 crvUSD/syrupUSDC pair and ramp its borrow limit to 7.5M";

    address public constant SYRUP_USDC_VAULT = 0xD0D347E14fbF1872affeaCb49d0b8B7182680E6C;
    uint256 public constant SYRUP_USDC_CONVEX_PID = 579;
    uint256 public constant TARGET_BORROW_LIMIT = 7_500_000e18;
    uint256 public constant RAMP_DURATION = 5 weeks;

    function run() public {
        IVoter.Action[] memory actions = buildProposalCalldata();
        printCallData(actions);

        vm.startBroadcast();
        (, address proposer,) = vm.readCallers();
        uint256 proposalId = voter.createNewProposal(proposer, actions, DESCRIPTION);
        vm.stopBroadcast();

        console.log("Proposal created by:", proposer);
        console.log("Proposal ID:", proposalId);
    }

    function buildProposalCalldata() public view returns (IVoter.Action[] memory actions) {
        require(
            IResupplyRegistry(Protocol.REGISTRY).getAddress("PAIR_DEPLOYER") ==
                address(pairDeployer),
            "Unexpected pair deployer"
        );
        _validateDefaultConfig();

        (address predictedPair, bytes memory deployPairData) =
            CurveLendV2PairDeployer.getDeployment(
                pairDeployer,
                SYRUP_USDC_VAULT,
                SYRUP_USDC_CONVEX_PID
            );
        require(predictedPair.code.length == 0, "syrupUSDC pair already deployed");
        uint256 rampEndTime =
            block.timestamp + voter.votingPeriod() + voter.executionDelay() + RAMP_DURATION;

        actions = new IVoter.Action[](3);

        // Deploy the Resupply pair using the standard configuration.
        actions[0] = IVoter.Action({
            target: address(pairDeployer),
            data: deployPairData
        });

        // Register the newly deployed pair.
        actions[1] = IVoter.Action({
            target: Protocol.REGISTRY,
            data: abi.encodeWithSelector(
                IResupplyRegistry.addPair.selector,
                predictedPair // pair to register
            )
        });

        // Ramp the borrow limit to 7.5M over five weeks after execution.
        actions[2] = IVoter.Action({
            target: Protocol.BORROW_LIMIT_CONTROLLER,
            data: abi.encodeWithSelector(
                IBorrowLimitController.setPairBorrowLimitRamp.selector,
                predictedPair, // pair
                TARGET_BORROW_LIMIT, // target borrow limit
                rampEndTime // ramp end timestamp
            )
        });
    }

    function getPairAddress() public view returns (address pair) {
        _validateDefaultConfig();
        (pair,) = CurveLendV2PairDeployer.getDeployment(
            pairDeployer,
            SYRUP_USDC_VAULT,
            SYRUP_USDC_CONVEX_PID
        );
    }

    function _validateDefaultConfig() internal view {
        ResupplyPairDeployer.ConfigData memory defaults =
            ResupplyPairDeployer(address(pairDeployer)).defaultConfigData();

        require(defaults.oracle == Protocol.BASIC_VAULT_ORACLE, "Unexpected default oracle");
        require(
            defaults.rateCalculator == 0xD3d5C6fc52f3bc29C3aB017d57D9A94A036Ca90f,
            "Unexpected default rate calculator"
        );
        require(defaults.maxLTV == 95_000, "Unexpected default max LTV");
        require(defaults.initialBorrowLimit == 1_000_000e18, "Unexpected default borrow limit");
        require(defaults.liquidationFee == 5_000, "Unexpected default liquidation fee");
        require(defaults.mintFee == 0, "Unexpected default mint fee");
        require(defaults.protocolRedemptionFee == 0.05e18, "Unexpected default redemption fee");
    }

    function printDefaultConfig() public view {
        ResupplyPairDeployer.ConfigData memory defaults =
            ResupplyPairDeployer(address(pairDeployer)).defaultConfigData();

        console.log("Default pair config");
        console.log("Oracle:", defaults.oracle);
        console.log("Rate calculator:", defaults.rateCalculator);
        console.log("Max LTV:", defaults.maxLTV);
        console.log("Initial borrow limit:", defaults.initialBorrowLimit);
        console.log("Liquidation fee:", defaults.liquidationFee);
        console.log("Mint fee:", defaults.mintFee);
        console.log("Protocol redemption fee:", defaults.protocolRedemptionFee);
    }

    function printCallData(IVoter.Action[] memory actions) public view {
        console.log("syrupUSDC pair:", getPairAddress());
        printDefaultConfig();
        for (uint256 i = 0; i < actions.length; i++) {
            console.log("Action", i + 1);
            console.log(actions[i].target);
            console.logBytes(actions[i].data);
            console.log("--------------------------------");
        }
    }
}
