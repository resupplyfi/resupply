// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Mainnet, Protocol } from "src/Constants.sol";
import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { CurveLendV2PairDeployer } from "script/actions/dependencies/CurveLendV2PairDeployer.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { ResupplyPairDeployer } from "src/protocol/ResupplyPairDeployer.sol";
import { console } from "lib/forge-std/src/console.sol";

contract DeploySyrupUsdcPair is BaseAction {
    IVoter public constant voter = IVoter(Protocol.VOTER);

    string public constant DESCRIPTION =
        "Deploy and register the CurveLendV2 crvUSD/syrupUSDC Resupply pair with borrowing disabled";

    address public constant SYRUP_USDC = 0x80ac24aA929eaF5013f6436cdA2a7ba190f5Cc0b;
    address public constant SYRUP_USDC_VAULT = 0xD0D347E14fbF1872affeaCb49d0b8B7182680E6C;
    uint256 public constant SYRUP_USDC_CONVEX_PID = 579;

    // Freeze the current standard pair configuration in proposal calldata,
    // except for the deliberately disabled initial borrow limit.
    address public constant ORACLE = Protocol.BASIC_VAULT_ORACLE;
    address public constant RATE_CALCULATOR = 0xD3d5C6fc52f3bc29C3aB017d57D9A94A036Ca90f;
    uint256 public constant MAX_LTV = 95_000;
    uint256 public constant INITIAL_BORROW_LIMIT = 0;
    uint256 public constant EXPECTED_DEFAULT_BORROW_LIMIT = 1_000_000e18;
    uint256 public constant LIQUIDATION_FEE = 5_000;
    uint256 public constant MINT_FEE = 0;
    uint256 public constant PROTOCOL_REDEMPTION_FEE = 0.05e18;

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
                _curveMarket(),
                INITIAL_BORROW_LIMIT
            );
        require(predictedPair.code.length == 0, "syrupUSDC pair already deployed");

        actions = new IVoter.Action[](2);

        // Deploy the Resupply pair with borrowing disabled.
        actions[0] = IVoter.Action({
            target: address(pairDeployer),
            data: deployPairData
        });

        // Register the newly deployed pair without scheduling a borrow-limit ramp.
        actions[1] = IVoter.Action({
            target: Protocol.REGISTRY,
            data: abi.encodeWithSelector(
                IResupplyRegistry.addPair.selector,
                predictedPair // pair to register
            )
        });
    }

    function getPairAddress() public view returns (address pair) {
        _validateDefaultConfig();
        (pair,) = CurveLendV2PairDeployer.getDeployment(
            pairDeployer,
            _curveMarket(),
            INITIAL_BORROW_LIMIT
        );
    }

    function _validateDefaultConfig() internal view {
        ResupplyPairDeployer.ConfigData memory defaults =
            ResupplyPairDeployer(address(pairDeployer)).defaultConfigData();

        require(defaults.oracle == ORACLE, "Unexpected default oracle");
        require(
            defaults.rateCalculator == RATE_CALCULATOR,
            "Unexpected default rate calculator"
        );
        require(defaults.maxLTV == MAX_LTV, "Unexpected default max LTV");
        require(
            defaults.initialBorrowLimit == EXPECTED_DEFAULT_BORROW_LIMIT,
            "Unexpected default borrow limit"
        );
        require(
            defaults.liquidationFee == LIQUIDATION_FEE,
            "Unexpected default liquidation fee"
        );
        require(defaults.mintFee == MINT_FEE, "Unexpected default mint fee");
        require(
            defaults.protocolRedemptionFee == PROTOCOL_REDEMPTION_FEE,
            "Unexpected default redemption fee"
        );
    }

    function _curveMarket() internal pure returns (CurveLendV2PairDeployer.Market memory market) {
        market = CurveLendV2PairDeployer.Market({
            factory: Mainnet.CURVE_LEND_V2_FACTORY,
            vault: SYRUP_USDC_VAULT,
            borrowedToken: Mainnet.CRVUSD_ERC20,
            collateralToken: SYRUP_USDC,
            convexPid: SYRUP_USDC_CONVEX_PID
        });
    }

    function printCallData(IVoter.Action[] memory actions) public view {
        console.log("syrupUSDC pair:", getPairAddress());
        for (uint256 i = 0; i < actions.length; i++) {
            console.log("Action", i + 1);
            console.log(actions[i].target);
            console.logBytes(actions[i].data);
            console.log("--------------------------------");
        }
    }
}
