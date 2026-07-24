// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IResupplyPairDeployer } from "src/interfaces/IResupplyPairDeployer.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IBorrowLimitController } from "src/interfaces/IBorrowLimitController.sol";
import { IConvexStaking } from "src/interfaces/convex/IConvexStaking.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { Mainnet, Protocol } from "src/Constants.sol";
import { ResupplyPairDeployer } from "src/protocol/ResupplyPairDeployer.sol";
import { DeployLlamaLendV2Pairs } from "script/proposals/DeployLlamaLendV2Pairs.s.sol";
import { BaseProposalTest } from "test/integration/proposals/BaseProposalTest.sol";

contract DeployLlamaLendV2PairsTest is BaseProposalTest {
    DeployLlamaLendV2Pairs public script;

    address public sdolaPair;
    address public sfrxUsdPair;
    string public sdolaPairName;
    string public sfrxUsdPairName;
    uint256 public pairCountBefore;

    uint256 public protocolCountBefore;
    uint256 public rampEndTime;

    address[7] internal actionTargets;
    bytes[] internal actionData;

    function setUp() public override {
        super.setUp();

        script = new DeployLlamaLendV2Pairs();
        pairCountBefore = registry.registeredPairsLength();
        protocolCountBefore = deployer.supportedProtocolsLength();
        sdolaPair = script.SDOLA_PAIR();
        sfrxUsdPair = script.SFRXUSD_PAIR();
        sdolaPairName = "Resupply Pair (CurveLendV2: crvUSD/sDOLA) - 1";
        sfrxUsdPairName = "Resupply Pair (CurveLendV2: crvUSD/sfrxUSD) - 1";
        rampEndTime = block.timestamp + voter.votingPeriod() + voter.executionDelay() + script.RAMP_DURATION();

        IVoter.Action[] memory actions = script.buildProposalCalldata();
        for (uint256 i = 0; i < actions.length; i++) {
            actionTargets[i] = actions[i].target;
            actionData.push(actions[i].data);
        }

        uint256 proposalId = createProposal(actions);
        simulatePassingVote(proposalId);
        executeProposal(proposalId);
    }

    function test_ProposalAddsLlamaLendV2Protocol() public view {
        assertEq(deployer.supportedProtocolsLength(), protocolCountBefore + 1, "protocol count mismatch");
        assertEq(deployer.platformNameById(Protocol.PROTOCOL_ID_CURVE_V2), script.PROTOCOL_NAME(), "protocol name mismatch");

        (string memory protocolName, uint256 amountToBurn, uint256 minShareBurnAmount, bytes4 borrowTokenSelector, bytes4 collateralTokenSelector) = deployer.supportedProtocols(Protocol.PROTOCOL_ID_CURVE_V2);

        assertEq(protocolName, script.PROTOCOL_NAME(), "stored protocol name mismatch");
        assertEq(amountToBurn, script.AMOUNT_TO_BURN(), "burn amount mismatch");
        assertEq(minShareBurnAmount, script.MIN_SHARE_BURN_AMOUNT(), "minimum burned shares mismatch");
        assertEq(borrowTokenSelector, script.BORROW_TOKEN_SELECTOR(), "borrow token selector mismatch");
        assertEq(collateralTokenSelector, script.COLLATERAL_TOKEN_SELECTOR(), "collateral token selector mismatch");
    }

    function test_ProposalDeploysAndRegistersBothPairs() public view {
        assertEq(registry.registeredPairsLength(), pairCountBefore + 2, "registry pair count mismatch");
        assertEq(registry.registeredPairs(pairCountBefore), sdolaPair, "sDOLA registry order mismatch");
        assertEq(registry.registeredPairs(pairCountBefore + 1), sfrxUsdPair, "sfrxUSD registry order mismatch");

        _assertPair(sdolaPair, script.SDOLA_VAULT(), sdolaPairName, script.SDOLA_CONVEX_PID());
        _assertPair(sfrxUsdPair, script.SFRXUSD_VAULT(), sfrxUsdPairName, script.SFRXUSD_CONVEX_PID());
    }

    function test_ProposalConfiguresBorrowLimitRamps() public {
        _assertRamp(sdolaPair, script.SDOLA_TARGET_BORROW_LIMIT());
        _assertRamp(sfrxUsdPair, script.SFRXUSD_TARGET_BORROW_LIMIT());

        skip(script.RAMP_DURATION() / 2);
        borrowLimitController.updatePairBorrowLimit(sdolaPair);
        borrowLimitController.updatePairBorrowLimit(sfrxUsdPair);

        assertGt(IResupplyPair(sdolaPair).borrowLimit(), 1_000_000e18, "sDOLA limit did not increase");
        assertLt(IResupplyPair(sdolaPair).borrowLimit(), script.SDOLA_TARGET_BORROW_LIMIT(), "sDOLA limit reached target early");
        assertGt(IResupplyPair(sfrxUsdPair).borrowLimit(), 1_000_000e18, "sfrxUSD limit did not increase");
        assertLt(IResupplyPair(sfrxUsdPair).borrowLimit(), script.SFRXUSD_TARGET_BORROW_LIMIT(), "sfrxUSD limit reached target early");

        skip(script.RAMP_DURATION() / 2);
        borrowLimitController.updatePairBorrowLimit(sdolaPair);
        borrowLimitController.updatePairBorrowLimit(sfrxUsdPair);

        assertEq(IResupplyPair(sdolaPair).borrowLimit(), script.SDOLA_TARGET_BORROW_LIMIT(), "sDOLA target limit mismatch");
        assertEq(IResupplyPair(sfrxUsdPair).borrowLimit(), script.SFRXUSD_TARGET_BORROW_LIMIT(), "sfrxUSD target limit mismatch");
    }

    function test_ProposalPayload() public view {
        assertEq(actionData.length, 7, "unexpected action count");

        assertEq(actionTargets[0], Protocol.PAIR_DEPLOYER_V2, "action 0 target");
        assertEq(keccak256(actionData[0]), keccak256(abi.encodeWithSelector(IResupplyPairDeployer.addSupportedProtocol.selector, script.PROTOCOL_NAME(), script.AMOUNT_TO_BURN(), script.MIN_SHARE_BURN_AMOUNT(), script.BORROW_TOKEN_SELECTOR(), script.COLLATERAL_TOKEN_SELECTOR())), "action 0 calldata");

        assertEq(actionTargets[1], Protocol.PAIR_DEPLOYER_V2, "action 1 target");
        assertEq(keccak256(actionData[1]), keccak256(abi.encodeWithSelector(IResupplyPairDeployer.deployWithDefaultConfig.selector, Protocol.PROTOCOL_ID_CURVE_V2, script.SDOLA_VAULT(), Mainnet.CONVEX_BOOSTER, script.SDOLA_CONVEX_PID())), "action 1 calldata");

        assertEq(actionTargets[2], Protocol.PAIR_DEPLOYER_V2, "action 2 target");
        assertEq(keccak256(actionData[2]), keccak256(abi.encodeWithSelector(IResupplyPairDeployer.deployWithDefaultConfig.selector, Protocol.PROTOCOL_ID_CURVE_V2, script.SFRXUSD_VAULT(), Mainnet.CONVEX_BOOSTER, script.SFRXUSD_CONVEX_PID())), "action 2 calldata");

        assertEq(actionTargets[3], Protocol.REGISTRY, "action 3 target");
        assertEq(keccak256(actionData[3]), keccak256(abi.encodeWithSelector(IResupplyRegistry.addPair.selector, sdolaPair)), "action 3 calldata");

        assertEq(actionTargets[4], Protocol.REGISTRY, "action 4 target");
        assertEq(keccak256(actionData[4]), keccak256(abi.encodeWithSelector(IResupplyRegistry.addPair.selector, sfrxUsdPair)), "action 4 calldata");

        assertEq(actionTargets[5], Protocol.BORROW_LIMIT_CONTROLLER, "action 5 target");
        assertEq(keccak256(actionData[5]), keccak256(abi.encodeWithSelector(IBorrowLimitController.setPairBorrowLimitRamp.selector, sdolaPair, script.SDOLA_TARGET_BORROW_LIMIT(), rampEndTime)), "action 5 calldata");

        assertEq(actionTargets[6], Protocol.BORROW_LIMIT_CONTROLLER, "action 6 target");
        assertEq(keccak256(actionData[6]), keccak256(abi.encodeWithSelector(IBorrowLimitController.setPairBorrowLimitRamp.selector, sfrxUsdPair, script.SFRXUSD_TARGET_BORROW_LIMIT(), rampEndTime)), "action 6 calldata");
    }

    function _assertRamp(address pair, uint256 targetBorrowLimit) internal view {
        IBorrowLimitController.PairBorrowLimit memory ramp = borrowLimitController.pairLimits(pair);
        assertEq(ramp.prevBorrowLimit, 1_000_000e18, "unexpected starting borrow limit");
        assertEq(ramp.targetBorrowLimit, targetBorrowLimit, "target borrow limit mismatch");
        assertEq(uint256(ramp.startTime), block.timestamp, "ramp start time mismatch");
        assertEq(uint256(ramp.endTime), rampEndTime, "ramp end time mismatch");
        assertEq(uint256(ramp.endTime) - uint256(ramp.startTime), script.RAMP_DURATION(), "ramp duration mismatch");
    }

    function _assertPair(address pairAddress, address vault, string memory expectedName, uint256 expectedPid) internal view {
        IResupplyPair pair = IResupplyPair(pairAddress);
        ResupplyPairDeployer.ConfigData memory config = ResupplyPairDeployer(address(deployer)).defaultConfigData();
        (uint40 protocolId, uint40 deployTime) = deployer.deployInfo(pairAddress);
        (address oracleAddress,,) = pair.exchangeRateInfo();

        assertGt(pairAddress.code.length, 0, "pair not deployed");
        assertEq(protocolId, Protocol.PROTOCOL_ID_CURVE_V2, "protocol ID mismatch");
        assertGt(deployTime, 0, "deploy time not recorded");
        assertEq(pair.name(), expectedName, "pair name mismatch");
        assertEq(registry.pairsByName(expectedName), pairAddress, "pair not registered by name");
        assertEq(pair.collateral(), vault, "pair collateral mismatch");
        assertEq(pair.underlying(), Mainnet.CRVUSD_ERC20, "pair underlying mismatch");
        assertEq(pair.convexBooster(), Mainnet.CONVEX_BOOSTER, "unexpected staking contract");
        assertEq(pair.convexPid(), expectedPid, "unexpected staking ID");
        (address lpToken,,,,, bool shutdown) = IConvexStaking(Mainnet.CONVEX_BOOSTER).poolInfo(expectedPid);
        assertEq(lpToken, vault, "Convex LP token mismatch");
        assertFalse(shutdown, "Convex pool is shutdown");
        assertEq(oracleAddress, config.oracle, "oracle mismatch");
        assertEq(pair.rateCalculator(), config.rateCalculator, "rate calculator mismatch");
        assertEq(pair.maxLTV(), config.maxLTV, "max LTV mismatch");
        assertEq(pair.borrowLimit(), config.initialBorrowLimit, "borrow limit mismatch");
        assertEq(pair.liquidationFee(), config.liquidationFee, "liquidation fee mismatch");
        assertEq(pair.mintFee(), config.mintFee, "mint fee mismatch");
        assertEq(pair.protocolRedemptionFee(), config.protocolRedemptionFee, "redemption fee mismatch");
    }
}
