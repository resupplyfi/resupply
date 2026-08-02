// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { CurveLendV2PairDeployer } from "script/actions/dependencies/CurveLendV2PairDeployer.sol";
import { DeploySyrupUsdcPair } from "script/proposals/DeploySyrupUsdcPair.s.sol";
import { Mainnet, Protocol } from "src/Constants.sol";
import { IBorrowLimitController } from "src/interfaces/IBorrowLimitController.sol";
import { IConvexStaking } from "src/interfaces/convex/IConvexStaking.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IResupplyPairDeployer } from "src/interfaces/IResupplyPairDeployer.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { ResupplyPairDeployer } from "src/protocol/ResupplyPairDeployer.sol";
import { BaseProposalTest } from "test/integration/proposals/BaseProposalTest.sol";

contract MockCurveLendV2Vault {
    address public immutable factory;

    constructor(address factory_) {
        factory = factory_;
    }
}

contract CurveLendV2PairDeploymentHarness is BaseAction {
    function validate(address vault, uint256 convexPid) external view returns (bool) {
        CurveLendV2PairDeployer.validate(vault, convexPid);
        return true;
    }

    function build(
        address vault,
        uint256 convexPid
    ) external view returns (address, bytes memory) {
        return CurveLendV2PairDeployer.getDeployment(
            pairDeployer,
            vault,
            convexPid
        );
    }
}

contract DeploySyrupUsdcPairTest is BaseProposalTest {
    DeploySyrupUsdcPair public script;
    CurveLendV2PairDeploymentHarness public helper;

    address public syrupUsdcPair;
    address public helperPredictedPair;
    bytes public helperDeploymentData;
    uint256 public pairCountBefore;
    uint256 public rampEndTime;
    ResupplyPairDeployer.ConfigData internal defaults;
    address[3] internal actionTargets;
    bytes[] internal actionData;

    function setUp() public override {
        super.setUp();

        script = new DeploySyrupUsdcPair();
        helper = new CurveLendV2PairDeploymentHarness();
        pairCountBefore = registry.registeredPairsLength();
        defaults = ResupplyPairDeployer(address(deployer)).defaultConfigData();
        syrupUsdcPair = script.getPairAddress();
        (helperPredictedPair, helperDeploymentData) = helper.build(
            script.SYRUP_USDC_VAULT(),
            script.SYRUP_USDC_CONVEX_PID()
        );
        rampEndTime =
            block.timestamp + voter.votingPeriod() + voter.executionDelay() + script.RAMP_DURATION();

        IVoter.Action[] memory actions = script.buildProposalCalldata();
        for (uint256 i = 0; i < actions.length; i++) {
            actionTargets[i] = actions[i].target;
            actionData.push(actions[i].data);
        }

        uint256 proposalId = createProposal(actions);
        simulatePassingVote(proposalId);
        executeProposal(proposalId);
    }

    function test_ProposalDeploysAndRegistersDefaultPair() public view {
        IResupplyPair pair = IResupplyPair(syrupUsdcPair);
        (uint40 protocolId, uint40 deployTime) = deployer.deployInfo(syrupUsdcPair);
        (address oracleAddress,,) = pair.exchangeRateInfo();

        assertGt(syrupUsdcPair.code.length, 0, "pair not deployed");
        assertEq(protocolId, Protocol.PROTOCOL_ID_CURVE_V2, "protocol ID mismatch");
        assertGt(deployTime, 0, "deploy time not recorded");
        assertEq(
            pair.name(),
            "Resupply Pair (CurveLendV2: crvUSD/syrupUSDC) - 1",
            "pair name mismatch"
        );
        assertEq(pair.collateral(), script.SYRUP_USDC_VAULT(), "pair collateral mismatch");
        assertEq(pair.underlying(), Mainnet.CRVUSD_ERC20, "pair underlying mismatch");
        assertEq(pair.convexBooster(), Mainnet.CONVEX_BOOSTER, "staking contract mismatch");
        assertEq(pair.convexPid(), script.SYRUP_USDC_CONVEX_PID(), "staking pool mismatch");
        assertEq(oracleAddress, defaults.oracle, "oracle mismatch");
        assertEq(pair.rateCalculator(), defaults.rateCalculator, "rate calculator mismatch");
        assertEq(pair.maxLTV(), defaults.maxLTV, "max LTV mismatch");
        assertEq(pair.borrowLimit(), defaults.initialBorrowLimit, "initial borrow limit mismatch");
        assertEq(pair.liquidationFee(), defaults.liquidationFee, "liquidation fee mismatch");
        assertEq(pair.mintFee(), defaults.mintFee, "mint fee mismatch");
        assertEq(
            pair.protocolRedemptionFee(),
            defaults.protocolRedemptionFee,
            "redemption fee mismatch"
        );

        assertEq(registry.registeredPairsLength(), pairCountBefore + 1, "registry length mismatch");
        assertEq(registry.registeredPairs(pairCountBefore), syrupUsdcPair, "registry pair mismatch");
        assertEq(registry.pairsByName(pair.name()), syrupUsdcPair, "pair name not registered");
    }

    function test_ProposalUsesCanonicalActiveConvexPool() public view {
        (address lpToken,,,,, bool shutdown) = IConvexStaking(Mainnet.CONVEX_BOOSTER)
            .poolInfo(script.SYRUP_USDC_CONVEX_PID());

        assertEq(lpToken, script.SYRUP_USDC_VAULT(), "Convex LP token mismatch");
        assertFalse(shutdown, "Convex pool is shutdown");
        assertGe(
            IERC20(script.SYRUP_USDC_VAULT()).balanceOf(address(0xdead)),
            1e20,
            "minimum vault shares not burned"
        );
    }

    function test_ProposalConfiguresBorrowLimitRamp() public view {
        IBorrowLimitController.PairBorrowLimit memory ramp = borrowLimitController.pairLimits(syrupUsdcPair);

        assertEq(ramp.prevBorrowLimit, defaults.initialBorrowLimit, "previous limit mismatch");
        assertEq(ramp.targetBorrowLimit, 7_500_000e18, "target limit mismatch");
        assertGt(ramp.startTime, 0, "ramp not started");
        assertEq(ramp.endTime, rampEndTime, "ramp end mismatch");
        assertEq(
            uint256(ramp.endTime) - uint256(ramp.startTime),
            45 days,
            "ramp duration mismatch"
        );
    }

    function test_ProposalPayload() public view {
        assertEq(actionData.length, 3, "unexpected action count");

        assertEq(actionTargets[0], Protocol.PAIR_DEPLOYER_V2, "action 0 target");
        assertEq(
            keccak256(actionData[0]),
            keccak256(
                abi.encodeWithSelector(
                    IResupplyPairDeployer.deployWithDefaultConfig.selector,
                    Protocol.PROTOCOL_ID_CURVE_V2,
                    script.SYRUP_USDC_VAULT(),
                    Mainnet.CONVEX_BOOSTER,
                    script.SYRUP_USDC_CONVEX_PID()
                )
            ),
            "action 0 calldata"
        );

        assertEq(actionTargets[1], Protocol.REGISTRY, "action 1 target");
        assertEq(
            keccak256(actionData[1]),
            keccak256(
                abi.encodeWithSelector(
                    IResupplyRegistry.addPair.selector,
                    syrupUsdcPair
                )
            ),
            "action 1 calldata"
        );

        assertEq(actionTargets[2], Protocol.BORROW_LIMIT_CONTROLLER, "action 2 target");
        assertEq(
            keccak256(actionData[2]),
            keccak256(
                abi.encodeWithSelector(
                    IBorrowLimitController.setPairBorrowLimitRamp.selector,
                    syrupUsdcPair,
                    script.TARGET_BORROW_LIMIT(),
                    rampEndTime
                )
            ),
            "action 2 calldata"
        );
    }

    function test_PairSupportsBorrowAndCollateralRoundTrip() public {
        IResupplyPair pair = IResupplyPair(syrupUsdcPair);
        address user = address(0xA11CE);
        uint256 assets = 2_000e18;

        deal(Mainnet.CRVUSD_ERC20, user, assets);
        vm.startPrank(user);
        IERC20(Mainnet.CRVUSD_ERC20).approve(syrupUsdcPair, assets);
        pair.addCollateral(assets, user);
        uint256 collateralShares = pair.userCollateralBalance(user);
        assertGt(collateralShares, 0, "no collateral shares received");

        uint256 borrowShares = pair.borrow(1_000e18, 0, user);
        IERC20(Protocol.STABLECOIN).approve(syrupUsdcPair, type(uint256).max);
        pair.repay(borrowShares, user);

        pair.removeCollateral(collateralShares, user);
        vm.stopPrank();

        assertEq(pair.userCollateralBalance(user), 0, "collateral not removed");
        assertEq(pair.totalCollateral(), 0, "pair collateral remains");
    }

    function test_HelperAcceptsCanonicalSyrupMarket() public view {
        assertTrue(
            _isValid(
                script.SYRUP_USDC_VAULT(),
                script.SYRUP_USDC_CONVEX_PID()
            )
        );
    }

    function test_HelperRejectsUnrecognizedFactory() public {
        address vault = address(new MockCurveLendV2Vault(Mainnet.CURVE_ONE_WAY_LENDING_FACTORY));
        uint256 convexPid = script.SYRUP_USDC_CONVEX_PID();

        assertFalse(_isValid(vault, convexPid));
    }

    function test_HelperRejectsNonVaultFactoryContract() public {
        address vault = address(new MockCurveLendV2Vault(Mainnet.CURVE_LEND_V2_FACTORY));
        uint256 convexPid = script.SYRUP_USDC_CONVEX_PID();

        assertFalse(_isValid(vault, convexPid));
    }

    function test_HelperRejectsWrongConvexPool() public {
        address vault = script.SYRUP_USDC_VAULT();

        assertFalse(_isValid(vault, 578));
    }

    function test_HelperBuildsExpectedDeployment() public view {
        assertEq(helperPredictedPair, syrupUsdcPair, "predicted pair mismatch");
        assertEq(
            keccak256(helperDeploymentData),
            keccak256(actionData[0]),
            "deployment calldata mismatch"
        );
    }

    function _isValid(address vault, uint256 convexPid) internal view returns (bool) {
        (bool success,) = address(helper).staticcall(
            abi.encodeCall(helper.validate, (vault, convexPid))
        );
        return success;
    }

}
