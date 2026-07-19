// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { Mainnet } from "src/Constants.sol";
import { TreasuryStableDiversification } from "src/dao/TreasuryStableDiversification.sol";
import { CurveProposalTreasuryStableDiversification } from "script/proposals/curve/CurveProposalTreasuryStableDiversification.s.sol";
import { BaseCurveProposalTest } from "test/integration/curveProposals/BaseCurveProposalTest.sol";

interface ICurvePoolView {
    // forge-lint: disable-next-line(mixed-case-function)
    function get_dy(int128 i, int128 j, uint256 dx) external view returns (uint256);
    // forge-lint: disable-next-line(mixed-case-function)
    function stored_rates() external view returns (uint256[] memory);
}

contract CurveProposalTreasuryStableDiversificationTest is BaseCurveProposalTest {
    uint256 internal constant FULL_BPS = 10_000;
    uint16 internal constant MAX_DEVIATION_BPS = 4;
    uint16 internal constant EXECUTION_BUFFER_BPS = 4;
    uint256 internal constant MAX_PRICE = 1.001e18;

    address internal constant CURVE_TREASURY = 0x6508eF65b0Bd57eaBD0f1D52685A70433B2d290B;
    address internal constant SDOLA = 0xb45ad160634c528Cc3D2926d9807104FA3157305;
    address internal constant SDOLA_SCRVUSD_POOL = 0x76A962BA6770068bCF454D34dDE17175611e6637;
    address internal constant FRXUSD = Mainnet.FRXUSD_ERC20;
    address internal constant SFRXUSD = Mainnet.SFRXUSD_ERC20;
    address internal constant CRVUSD_FRXUSD_POOL = 0x13e12BB0E6A2f1A3d6901a59a9d585e89A6243e1;
    address internal constant FRXUSD_SFRXUSD_POOL = 0xF292eB6c5dcb693Eaaf392D0562a01C3710E5978;

    CurveProposalTreasuryStableDiversification internal proposalScript;
    TreasuryStableDiversification internal diversifier;

    function setUp() public override {
        super.setUp();

        proposalScript = new CurveProposalTreasuryStableDiversification();
        diversifier = new TreasuryStableDiversification(
            address(this),
            CURVE_TREASURY,
            Mainnet.CRVUSD_ERC20,
            MAX_DEVIATION_BPS
        );
        diversifier.setTargets(_buildTargets());
        diversifier.transferOwnership(Mainnet.CURVE_OWNERSHIP_AGENT);

        proposalScript.setDeployAddresses(address(diversifier), CURVE_TREASURY);
        bytes memory script = proposalScript.buildProposalScript();
        uint256 proposalId = proposeOwnershipVote(
            script,
            "Accept TreasuryStableDiversification ownership and approve treasury crvUSD"
        );
        simulatePassingProposal(proposalId);
    }

    function test_ProposalAcceptedOwnershipAndApprovedTreasuryCrvUsd() public view {
        assertEq(diversifier.owner(), Mainnet.CURVE_OWNERSHIP_AGENT);
        assertEq(diversifier.pendingOwner(), address(0));
        assertEq(
            IERC20(Mainnet.CRVUSD_ERC20).allowance(CURVE_TREASURY, address(diversifier)),
            type(uint256).max
        );
    }

    function test_CanSwapTreasuryCrvUsdToSdolaAndSfrxUsdAfterProposal() public {
        uint256 amount = 100e18;
        assertGe(IERC20(Mainnet.CRVUSD_ERC20).balanceOf(CURVE_TREASURY), amount);

        uint256 treasuryCrvUsdBefore = IERC20(Mainnet.CRVUSD_ERC20).balanceOf(CURVE_TREASURY);
        uint256 treasurySdolaBefore = IERC20(SDOLA).balanceOf(CURVE_TREASURY);
        uint256 treasurySfrxUsdBefore = IERC20(SFRXUSD).balanceOf(CURVE_TREASURY);

        uint256[] memory sdolaScrvRates = ICurvePoolView(SDOLA_SCRVUSD_POOL).stored_rates();
        assertApproxEqAbs(sdolaScrvRates[0], IERC4626(Mainnet.SCRVUSD_ERC20).convertToAssets(1e18), 1);
        assertApproxEqAbs(sdolaScrvRates[1], IERC4626(SDOLA).convertToAssets(1e18), 1);

        uint256[] memory sfrxUsdRates = ICurvePoolView(FRXUSD_SFRXUSD_POOL).stored_rates();
        assertApproxEqAbs(sfrxUsdRates[0], IERC4626(SFRXUSD).convertToAssets(1e18), 1);
        assertEq(sfrxUsdRates[1], 1e18);

        uint256 expectedScrvUsdShares = IERC4626(Mainnet.SCRVUSD_ERC20).convertToShares(25e18);
        uint256 expectedScrvUsdAssets = IERC4626(Mainnet.SCRVUSD_ERC20).convertToAssets(expectedScrvUsdShares);
        uint256 expectedSdolaShares = ICurvePoolView(SDOLA_SCRVUSD_POOL).get_dy(0, 1, expectedScrvUsdShares);
        uint256 minSdolaShares = IERC4626(SDOLA).convertToShares(expectedScrvUsdAssets)
            * (FULL_BPS - MAX_DEVIATION_BPS) / FULL_BPS;

        uint256 expectedFrxUsd = ICurvePoolView(CRVUSD_FRXUSD_POOL).get_dy(1, 0, 75e18);
        uint256 expectedSfrxUsdShares = ICurvePoolView(FRXUSD_SFRXUSD_POOL).get_dy(1, 0, expectedFrxUsd);
        uint256 minSfrxUsdShares = IERC4626(SFRXUSD).convertToShares(expectedFrxUsd * 1e18 / MAX_PRICE)
            * (FULL_BPS - EXECUTION_BUFFER_BPS) / FULL_BPS;

        uint256 swapped = diversifier.swap(amount);

        uint256 sdolaReceived = IERC20(SDOLA).balanceOf(CURVE_TREASURY) - treasurySdolaBefore;
        uint256 sfrxUsdReceived = IERC20(SFRXUSD).balanceOf(CURVE_TREASURY) - treasurySfrxUsdBefore;

        assertEq(swapped, amount);
        assertEq(treasuryCrvUsdBefore - IERC20(Mainnet.CRVUSD_ERC20).balanceOf(CURVE_TREASURY), amount);
        assertApproxEqAbs(sdolaReceived, expectedSdolaShares, 1);
        assertApproxEqAbs(sfrxUsdReceived, expectedSfrxUsdShares, 1);
        assertGe(sdolaReceived, minSdolaShares);
        assertGe(sfrxUsdReceived, minSfrxUsdShares);
        assertEq(IERC20(Mainnet.CRVUSD_ERC20).balanceOf(address(diversifier)), 0);
        assertEq(IERC20(Mainnet.SCRVUSD_ERC20).balanceOf(address(diversifier)), 0);
        assertEq(IERC20(FRXUSD).balanceOf(address(diversifier)), 0);
        assertEq(IERC20(SDOLA).balanceOf(address(diversifier)), 0);
        assertEq(IERC20(SFRXUSD).balanceOf(address(diversifier)), 0);
    }

    function _buildTargets() internal pure returns (TreasuryStableDiversification.Target[] memory targets) {
        targets = new TreasuryStableDiversification.Target[](3);
        targets[0] = TreasuryStableDiversification.Target({
            token: SDOLA,
            weight: 25,
            swapPool: SDOLA_SCRVUSD_POOL,
            vault: address(0),
            inputToken: address(0),
            stakedAsset: Mainnet.SCRVUSD_ERC20,
            maxPrice: 0,
            maxSpotEmaDeviationBps: MAX_DEVIATION_BPS,
            executionBufferBps: 0
        });
        targets[1] = TreasuryStableDiversification.Target({
            token: FRXUSD,
            weight: 75,
            swapPool: CRVUSD_FRXUSD_POOL,
            vault: address(0),
            inputToken: address(0),
            stakedAsset: address(0),
            maxPrice: MAX_PRICE,
            maxSpotEmaDeviationBps: MAX_DEVIATION_BPS,
            executionBufferBps: EXECUTION_BUFFER_BPS
        });
        targets[2] = TreasuryStableDiversification.Target({
            token: SFRXUSD,
            weight: 0,
            swapPool: FRXUSD_SFRXUSD_POOL,
            vault: address(0),
            inputToken: FRXUSD,
            stakedAsset: address(0),
            maxPrice: MAX_PRICE,
            maxSpotEmaDeviationBps: MAX_DEVIATION_BPS,
            executionBufferBps: EXECUTION_BUFFER_BPS
        });
    }
}
