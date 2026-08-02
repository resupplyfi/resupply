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
import { BaseProposalTest } from "test/integration/proposals/BaseProposalTest.sol";

contract CurveLendV2PairDeploymentHarness is BaseAction {
    function validate(CurveLendV2PairDeployer.Market memory market) external view {
        CurveLendV2PairDeployer.validate(market);
    }

    function build(
        CurveLendV2PairDeployer.Market memory market,
        uint256 initialBorrowLimit
    ) external view returns (address, bytes memory) {
        return CurveLendV2PairDeployer.getDeployment(
            pairDeployer,
            market,
            initialBorrowLimit
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
    address[2] internal actionTargets;
    bytes[] internal actionData;

    function setUp() public override {
        super.setUp();

        script = new DeploySyrupUsdcPair();
        helper = new CurveLendV2PairDeploymentHarness();
        pairCountBefore = registry.registeredPairsLength();
        syrupUsdcPair = script.getPairAddress();
        (helperPredictedPair, helperDeploymentData) = helper.build(
            _market(),
            script.INITIAL_BORROW_LIMIT()
        );

        IVoter.Action[] memory actions = script.buildProposalCalldata();
        for (uint256 i = 0; i < actions.length; i++) {
            actionTargets[i] = actions[i].target;
            actionData.push(actions[i].data);
        }

        uint256 proposalId = createProposal(actions);
        simulatePassingVote(proposalId);
        executeProposal(proposalId);
    }

    function test_ProposalDeploysAndRegistersDisabledPair() public view {
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
        assertEq(oracleAddress, script.ORACLE(), "oracle mismatch");
        assertEq(pair.rateCalculator(), script.RATE_CALCULATOR(), "rate calculator mismatch");
        assertEq(pair.maxLTV(), script.MAX_LTV(), "max LTV mismatch");
        assertEq(pair.borrowLimit(), 0, "pair should start disabled");
        assertEq(pair.liquidationFee(), script.LIQUIDATION_FEE(), "liquidation fee mismatch");
        assertEq(pair.mintFee(), script.MINT_FEE(), "mint fee mismatch");
        assertEq(
            pair.protocolRedemptionFee(),
            script.PROTOCOL_REDEMPTION_FEE(),
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

    function test_ProposalHasNoBorrowLimitRamp() public view {
        IBorrowLimitController.PairBorrowLimit memory ramp = borrowLimitController.pairLimits(syrupUsdcPair);

        assertEq(ramp.prevBorrowLimit, 0, "unexpected previous limit");
        assertEq(ramp.targetBorrowLimit, 0, "unexpected target limit");
        assertEq(ramp.startTime, 0, "unexpected ramp start");
        assertEq(ramp.endTime, 0, "unexpected ramp end");
    }

    function test_ProposalPayload() public view {
        assertEq(actionData.length, 2, "unexpected action count");

        assertEq(actionTargets[0], Protocol.PAIR_DEPLOYER_V2, "action 0 target");
        assertEq(
            keccak256(actionData[0]),
            keccak256(
                abi.encodeWithSelector(
                    IResupplyPairDeployer.deploy.selector,
                    Protocol.PROTOCOL_ID_CURVE_V2,
                    _expectedConfigData(),
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
    }

    function test_PairSupportsCollateralRoundTripWhileBorrowingIsDisabled() public {
        IResupplyPair pair = IResupplyPair(syrupUsdcPair);
        address user = address(0xA11CE);
        uint256 assets = 100e18;

        deal(Mainnet.CRVUSD_ERC20, user, assets);
        vm.startPrank(user);
        IERC20(Mainnet.CRVUSD_ERC20).approve(syrupUsdcPair, assets);
        pair.addCollateral(assets, user);
        uint256 collateralShares = pair.userCollateralBalance(user);
        assertGt(collateralShares, 0, "no collateral shares received");

        vm.expectRevert();
        pair.borrow(1e18, 0, user);

        pair.removeCollateral(collateralShares, user);
        vm.stopPrank();

        assertEq(pair.userCollateralBalance(user), 0, "collateral not removed");
        assertEq(pair.totalCollateral(), 0, "pair collateral remains");
    }

    function test_HelperAcceptsCanonicalSyrupMarket() public view {
        helper.validate(_market());
    }

    function test_HelperRejectsUnrecognizedFactory() public {
        CurveLendV2PairDeployer.Market memory market = _market();
        market.factory = Mainnet.CURVE_ONE_WAY_LENDING_FACTORY;

        vm.expectRevert(bytes("Unrecognized LLv2 factory"));
        helper.validate(market);
    }

    function test_HelperRejectsNonVaultFactoryContract() public {
        CurveLendV2PairDeployer.Market memory market = _market();
        market.vault = 0x2fb54c8eae57767A9A509A395b9C4FA0702e2675; // syrupUSDC controller

        vm.expectRevert(bytes("LLv2 asset is not a factory vault"));
        helper.validate(market);
    }

    function test_HelperRejectsUnexpectedBorrowedToken() public {
        CurveLendV2PairDeployer.Market memory market = _market();
        market.borrowedToken = address(0xB0);

        vm.expectRevert(bytes("Unexpected LLv2 borrowed token"));
        helper.validate(market);
    }

    function test_HelperRejectsUnexpectedCollateralToken() public {
        CurveLendV2PairDeployer.Market memory market = _market();
        market.collateralToken = address(0xC0);

        vm.expectRevert(bytes("Unexpected LLv2 collateral token"));
        helper.validate(market);
    }

    function test_HelperRejectsWrongConvexPool() public {
        CurveLendV2PairDeployer.Market memory market = _market();
        market.convexPid = 578;

        vm.expectRevert(bytes("Staking pool collateral mismatch"));
        helper.validate(market);
    }

    function test_HelperBuildsExpectedDeployment() public view {
        assertEq(helperPredictedPair, syrupUsdcPair, "predicted pair mismatch");
        assertEq(
            keccak256(helperDeploymentData),
            keccak256(actionData[0]),
            "deployment calldata mismatch"
        );
    }

    function _market() internal view returns (CurveLendV2PairDeployer.Market memory market) {
        market = CurveLendV2PairDeployer.Market({
            factory: Mainnet.CURVE_LEND_V2_FACTORY,
            vault: script.SYRUP_USDC_VAULT(),
            borrowedToken: Mainnet.CRVUSD_ERC20,
            collateralToken: script.SYRUP_USDC(),
            convexPid: script.SYRUP_USDC_CONVEX_PID()
        });
    }

    function _expectedConfigData() internal view returns (bytes memory) {
        return abi.encode(
            script.SYRUP_USDC_VAULT(), // collateral vault
            script.ORACLE(), // oracle
            script.RATE_CALCULATOR(), // rate calculator
            script.MAX_LTV(), // max LTV
            script.INITIAL_BORROW_LIMIT(), // initial borrow limit: disabled
            script.LIQUIDATION_FEE(), // liquidation fee
            script.MINT_FEE(), // mint fee
            script.PROTOCOL_REDEMPTION_FEE() // protocol share of redemption fees
        );
    }
}
