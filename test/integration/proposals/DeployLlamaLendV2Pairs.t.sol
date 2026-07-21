// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IResupplyPairDeployer } from "src/interfaces/IResupplyPairDeployer.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
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

    address[4] internal actionTargets;
    bytes[] internal actionData;

    function setUp() public override {
        super.setUp();

        script = new DeployLlamaLendV2Pairs();
        pairCountBefore = registry.registeredPairsLength();
        (sdolaPair, sfrxUsdPair) = script.getPredictedPairAddresses();
        (sdolaPairName,,) = deployer.getNextName(Protocol.PROTOCOL_ID_CURVE, script.SDOLA_VAULT());
        (sfrxUsdPairName,,) = deployer.getNextName(Protocol.PROTOCOL_ID_CURVE, script.SFRXUSD_VAULT());

        IVoter.Action[] memory actions = script.buildProposalCalldata();
        for (uint256 i = 0; i < actions.length; i++) {
            actionTargets[i] = actions[i].target;
            actionData.push(actions[i].data);
        }

        uint256 proposalId = createProposal(actions);
        simulatePassingVote(proposalId);
        executeProposal(proposalId);
    }

    function test_ProposalDeploysAndRegistersBothPairs() public view {
        assertEq(registry.registeredPairsLength(), pairCountBefore + 2, "registry pair count mismatch");
        assertEq(registry.registeredPairs(pairCountBefore), sdolaPair, "sDOLA registry order mismatch");
        assertEq(registry.registeredPairs(pairCountBefore + 1), sfrxUsdPair, "sfrxUSD registry order mismatch");

        _assertPair(sdolaPair, script.SDOLA_VAULT(), sdolaPairName);
        _assertPair(sfrxUsdPair, script.SFRXUSD_VAULT(), sfrxUsdPairName);
    }

    function test_ProposalPayload() public view {
        assertEq(actionData.length, 4, "unexpected action count");

        assertEq(actionTargets[0], Protocol.PAIR_DEPLOYER_V2, "action 0 target");
        assertEq(keccak256(actionData[0]), keccak256(abi.encodeWithSelector(IResupplyPairDeployer.deployWithDefaultConfig.selector, Protocol.PROTOCOL_ID_CURVE, script.SDOLA_VAULT(), address(0), 0)), "action 0 calldata");

        assertEq(actionTargets[1], Protocol.REGISTRY, "action 1 target");
        assertEq(keccak256(actionData[1]), keccak256(abi.encodeWithSelector(IResupplyRegistry.addPair.selector, sdolaPair)), "action 1 calldata");

        assertEq(actionTargets[2], Protocol.PAIR_DEPLOYER_V2, "action 2 target");
        assertEq(keccak256(actionData[2]), keccak256(abi.encodeWithSelector(IResupplyPairDeployer.deployWithDefaultConfig.selector, Protocol.PROTOCOL_ID_CURVE, script.SFRXUSD_VAULT(), address(0), 0)), "action 2 calldata");

        assertEq(actionTargets[3], Protocol.REGISTRY, "action 3 target");
        assertEq(keccak256(actionData[3]), keccak256(abi.encodeWithSelector(IResupplyRegistry.addPair.selector, sfrxUsdPair)), "action 3 calldata");
    }

    function test_RegisteredPairsSupportBorrowRoundTrip() public {
        _exercisePair(IResupplyPair(sdolaPair));
        _exercisePair(IResupplyPair(sfrxUsdPair));
    }

    function _assertPair(address pairAddress, address vault, string memory expectedName) internal view {
        IResupplyPair pair = IResupplyPair(pairAddress);
        ResupplyPairDeployer.ConfigData memory config = ResupplyPairDeployer(address(deployer)).defaultConfigData();
        (uint40 protocolId, uint40 deployTime) = deployer.deployInfo(pairAddress);
        (address oracleAddress,,) = pair.exchangeRateInfo();

        assertGt(pairAddress.code.length, 0, "pair not deployed");
        assertEq(protocolId, Protocol.PROTOCOL_ID_CURVE, "protocol ID mismatch");
        assertGt(deployTime, 0, "deploy time not recorded");
        assertEq(pair.name(), expectedName, "pair name mismatch");
        assertEq(registry.pairsByName(expectedName), pairAddress, "pair not registered by name");
        assertEq(pair.collateral(), vault, "pair collateral mismatch");
        assertEq(pair.underlying(), Mainnet.CRVUSD_ERC20, "pair underlying mismatch");
        assertEq(pair.convexBooster(), address(0), "unexpected staking contract");
        assertEq(pair.convexPid(), 0, "unexpected staking ID");
        assertEq(oracleAddress, config.oracle, "oracle mismatch");
        assertEq(pair.rateCalculator(), config.rateCalculator, "rate calculator mismatch");
        assertEq(pair.maxLTV(), config.maxLTV, "max LTV mismatch");
        assertEq(pair.borrowLimit(), config.initialBorrowLimit, "borrow limit mismatch");
        assertEq(pair.liquidationFee(), config.liquidationFee, "liquidation fee mismatch");
        assertEq(pair.mintFee(), config.mintFee, "mint fee mismatch");
        assertEq(pair.protocolRedemptionFee(), config.protocolRedemptionFee, "redemption fee mismatch");
    }

    function _exercisePair(IResupplyPair pair) internal {
        address account = address(uint160(uint256(keccak256(abi.encode(address(pair))))));
        deal(Mainnet.CRVUSD_ERC20, account, 5000e18);

        vm.startPrank(account);
        IERC20(Mainnet.CRVUSD_ERC20).approve(address(pair), type(uint256).max);
        pair.addCollateral(2000e18, account);

        uint256 collateralShares = pair.userCollateralBalance(account);
        uint256 borrowShares = pair.borrow(1000e18, 0, account);
        assertGt(collateralShares, 0, "collateral shares not minted");
        assertGt(borrowShares, 0, "borrow shares not minted");

        IERC20(Protocol.STABLECOIN).approve(address(pair), type(uint256).max);
        pair.repay(borrowShares, account);
        pair.removeCollateral(collateralShares, account);
        vm.stopPrank();

        assertEq(pair.userBorrowShares(account), 0, "borrow shares remain");
        assertEq(pair.userCollateralBalance(account), 0, "collateral remains");
    }
}
