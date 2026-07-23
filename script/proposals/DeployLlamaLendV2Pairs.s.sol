// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Mainnet, Protocol } from "src/Constants.sol";
import { Script } from "lib/forge-std/src/Script.sol";
import { console } from "lib/forge-std/src/console.sol";
import { IBorrowLimitController } from "src/interfaces/IBorrowLimitController.sol";
import { IResupplyPairDeployer } from "src/interfaces/IResupplyPairDeployer.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IVoter } from "src/interfaces/IVoter.sol";

contract DeployLlamaLendV2Pairs is Script {
    IResupplyPairDeployer public constant pairDeployer = IResupplyPairDeployer(Protocol.PAIR_DEPLOYER_V2);
    IVoter public constant voter = IVoter(Protocol.VOTER);

    string public constant DESCRIPTION = "Add CurveLendV2 support and deploy and register the sDOLA/crvUSD and sfrxUSD/crvUSD pairs";

    string public constant PROTOCOL_NAME = "CurveLendV2";

    // Settings for adding new Protocol to PairDeploy
    uint256 public constant AMOUNT_TO_BURN = 1e18;
    uint256 public constant MIN_SHARE_BURN_AMOUNT = 1e20;
    bytes4 public constant BORROW_TOKEN_SELECTOR = 0x38d52e0f; // asset()
    bytes4 public constant COLLATERAL_TOKEN_SELECTOR = 0x2621db2f; // collateral_token()

    // New Pair Settings
    address public constant SDOLA_VAULT = 0x2b5a321C3cb1F33e1ABECD047C2649D0b4C47eBa;
    address public constant SFRXUSD_VAULT = 0x3Da0F110079012387F47C6Fc6e878F10262E300a;
    uint256 public constant SDOLA_CONVEX_PID = 570;
    uint256 public constant SFRXUSD_CONVEX_PID = 571;

    // Borrow Limit Controller Settings
    uint256 public constant SDOLA_TARGET_BORROW_LIMIT = 10_000_000e18;
    uint256 public constant SFRXUSD_TARGET_BORROW_LIMIT = 20_000_000e18;
    uint256 public constant RAMP_DURATION = 45 days;

    // The new protocol ID does not exist until action 0 executes, so the
    // factory cannot predict these addresses while this proposal is built.
    // The constants are CREATE2 predictions verified in the proposal test.
    address public constant SDOLA_PAIR = 0xEcceF525b3063705DA5075a1ce5De1892D24C25A;
    address public constant SFRXUSD_PAIR = 0x0837E20D15585B4cA5c1a3fCedCCF8f72855Cb56;

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
            pairDeployer.supportedProtocolsLength() ==
                Protocol.PROTOCOL_ID_CURVE_V2,
            "unexpected next protocol ID"
        );

        bytes memory addProtocol = abi.encodeWithSelector(
            IResupplyPairDeployer.addSupportedProtocol.selector,
            PROTOCOL_NAME,
            AMOUNT_TO_BURN,
            MIN_SHARE_BURN_AMOUNT,
            BORROW_TOKEN_SELECTOR,
            COLLATERAL_TOKEN_SELECTOR
        );

        // deployWithDefaultConfig reads the deployer's stored defaults when
        // each action executes. At proposal time, those defaults are:
        // - oracle: BasicVaultOracle (0xa346BA5E838D6Ee40204A69549c81AB982644150)
        // - rate calculator: InterestRateCalculator v2.1.1 (0xD3d5C6fc52f3bc29C3aB017d57D9A94A036Ca90f)
        // - max LTV: 95%; initial borrow limit: 1,000,000 reUSD
        // - liquidation fee: 5%; mint fee: 0%
        // - protocol redemption share: 5% of the redemption fee
        bytes memory deploySdolaPair = abi.encodeWithSelector(
            IResupplyPairDeployer.deployWithDefaultConfig.selector,
            Protocol.PROTOCOL_ID_CURVE_V2,
            SDOLA_VAULT,
            Mainnet.CONVEX_BOOSTER,
            SDOLA_CONVEX_PID
        );
        bytes memory deploySfrxUsdPair = abi.encodeWithSelector(
            IResupplyPairDeployer.deployWithDefaultConfig.selector,
            Protocol.PROTOCOL_ID_CURVE_V2,
            SFRXUSD_VAULT,
            Mainnet.CONVEX_BOOSTER,
            SFRXUSD_CONVEX_PID
        );
        uint256 rampEndTime = block.timestamp + voter.votingPeriod() + voter.executionDelay() + RAMP_DURATION;

        actions = new IVoter.Action[](7);

        // Add CurveLend V2 protocol support.
        actions[0] = IVoter.Action({
            target: address(pairDeployer),
            data: addProtocol
        });

        // Deploy both pairs.
        actions[1] = IVoter.Action({
            target: address(pairDeployer),
            data: deploySdolaPair
        });
        actions[2] = IVoter.Action({
            target: address(pairDeployer),
            data: deploySfrxUsdPair
        });

        // Register both pairs.
        actions[3] = IVoter.Action({
            target: Protocol.REGISTRY,
            data: abi.encodeWithSelector(
                IResupplyRegistry.addPair.selector,
                SDOLA_PAIR
            )
        });
        actions[4] = IVoter.Action({
            target: Protocol.REGISTRY,
            data: abi.encodeWithSelector(
                IResupplyRegistry.addPair.selector,
                SFRXUSD_PAIR
            )
        });

        // Configure both borrow limit ramps.
        actions[5] = IVoter.Action({
            target: Protocol.BORROW_LIMIT_CONTROLLER,
            data: abi.encodeWithSelector(
                IBorrowLimitController.setPairBorrowLimitRamp.selector,
                SDOLA_PAIR,
                SDOLA_TARGET_BORROW_LIMIT,
                rampEndTime
            )
        });
        actions[6] = IVoter.Action({
            target: Protocol.BORROW_LIMIT_CONTROLLER,
            data: abi.encodeWithSelector(
                IBorrowLimitController.setPairBorrowLimitRamp.selector,
                SFRXUSD_PAIR,
                SFRXUSD_TARGET_BORROW_LIMIT,
                rampEndTime
            )
        });
    }

    function printCallData(IVoter.Action[] memory actions) public view {
        for (uint256 i = 0; i < actions.length; i++) {
            console.log("Action", i + 1);
            console.log(actions[i].target);
            console.logBytes(actions[i].data);
            console.log("--------------------------------");
        }
    }
}
