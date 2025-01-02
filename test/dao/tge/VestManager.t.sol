pragma solidity ^0.8.22;

import { Setup } from "../../Setup.sol";
import { VestManager } from "../../../src/dao/tge/VestManager.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { console } from "../../../lib/forge-std/src/console.sol";
import { MockToken } from "../../mocks/MockToken.sol";
import { VestManagerInitParams } from "../../helpers/VestManagerInitParams.sol";
import { AutoStakeCallback } from "src/dao/tge/AutoStakeCallback.sol";


contract VestManagerHarness is Setup {
    // Max amount of redeemable PRISMA/yPRISMA/cvxPRISMA
    uint256 maxRedeemable = 150_000_000e18;
    AutoStakeCallback autoStakeCallback;

    function setUp() public override {
        super.setUp();
        autoStakeCallback = new AutoStakeCallback(address(core), address(staker), address(vestManager));
        assertEq(vestManager.redemptionRatio(), 0);
        address prisma = address(vestManager.prisma());
        vm.expectRevert("ratio not set");
        vestManager.redeem(prisma, address(this), 1e18);

        VestManagerInitParams.InitParams memory params = VestManagerInitParams.getInitParams(
            address(permaStaker1),
            address(permaStaker2),
            address(treasury)
        );
        vm.prank(address(core));
        vestManager.setInitializationParams(
            params.maxRedeemable,      // _maxRedeemable
            params.merkleRoots,
            params.nonUserTargets,
            params.durations,
            params.allocPercentages
        );
    }

    function test_VestDurations() public {
        assertEq(vestManager.durationByType(VestManager.AllocationType.TREASURY), 5 * 365 days, 'TREASURY not 5 years');
        assertEq(vestManager.durationByType(VestManager.AllocationType.PERMA_LOCK), 5 * 365 days, 'PERMA_LOCK not 5 years');
        assertEq(vestManager.durationByType(VestManager.AllocationType.LICENSING), 1 * 365 days, 'LICENSING not 1 years');
        assertEq(vestManager.durationByType(VestManager.AllocationType.REDEMPTIONS), 5 * 365 days, 'REDEMPTIONS not 5 years');
        assertEq(vestManager.durationByType(VestManager.AllocationType.AIRDROP_TEAM), 1 * 365 days, 'AIRDROP_TEAM not 1 year');
        assertEq(vestManager.durationByType(VestManager.AllocationType.AIRDROP_VICTIMS), 2 * 365 days, 'AIRDROP_VICTIMS not 2 years');
        assertEq(vestManager.durationByType(VestManager.AllocationType.AIRDROP_LOCK_PENALTY), 5 * 365 days, 'AIRDROP_LOCK_PENALTY not 5 years');

        assertEq(vestManager.numAccountVests(address(permaStaker1)), 1);
        assertEq(vestManager.numAccountVests(address(permaStaker2)), 1);
        assertEq(vestManager.numAccountVests(FRAX_VEST_TARGET), 1);


        (uint256 total, uint256 claimable, uint256 claimed, uint256 timeRemaining) = vestManager.getSingleVestData(address(treasury), 0);
        assertEq(claimable, 0, 'claimable not 0');
        assertGt(total, 0, 'total not > 0');
        assertEq(claimed, 0, 'claimed not 0');
        assertEq(timeRemaining, 5 * 365 days, 'timeRemaining not 5 years');

        (total, claimable, claimed, timeRemaining) = vestManager.getSingleVestData(address(permaStaker1), 0);
        assertEq(claimable, 0, 'claimable not 0');
        assertGt(total, 0, 'total not > 0');
        assertEq(claimed, 0, 'claimed not 0');
        assertEq(timeRemaining, 5 * 365 days, 'timeRemaining not 5 years');

        (total, claimable, claimed, timeRemaining) = vestManager.getSingleVestData(address(permaStaker2), 0);
        assertEq(claimable, 0, 'claimable not 0');
        assertGt(total, 0, 'total not > 0');
        assertEq(claimed, 0, 'claimed not 0');
        assertEq(timeRemaining, 5 * 365 days, 'timeRemaining not 5 years'); 

        (total, claimable, claimed, timeRemaining) = vestManager.getSingleVestData(FRAX_VEST_TARGET, 0);
        assertEq(claimable, 0, 'claimable not 0');
        assertGt(total, 0, 'total not > 0');
        assertEq(claimed, 0, 'claimed not 0');
        assertEq(timeRemaining, 1 * 365 days, 'timeRemaining not 1 year');

        skip(365 days);

        (total, claimable, claimed, timeRemaining) = vestManager.getSingleVestData(address(treasury), 0);
        assertEq(claimable, total / 5, 'claimable not total / 5');
        assertGt(total, 0, 'total not > 0');
        assertEq(claimed, 0, 'claimed not 0');
        assertEq(timeRemaining, 4 * 365 days, 'timeRemaining not 4 years');

        (total, claimable, claimed, timeRemaining) = vestManager.getSingleVestData(address(permaStaker1), 0);
        assertEq(claimable, total / 5, 'claimable not total / 5');
        assertGt(total, 0, 'total not > 0');
        assertEq(claimed, 0, 'claimed not 0');
        assertEq(timeRemaining, 4 * 365 days, 'timeRemaining not 4 years');

        (total, claimable, claimed, timeRemaining) = vestManager.getSingleVestData(address(permaStaker2), 0);
        assertEq(claimable, total / 5, 'claimable not total / 5');
        assertGt(total, 0, 'total not > 0');
        assertEq(claimed, 0, 'claimed not 0');
        assertEq(timeRemaining, 4 * 365 days, 'timeRemaining not 4 years');

        (total, claimable, claimed, timeRemaining) = vestManager.getSingleVestData(FRAX_VEST_TARGET, 0);
        assertEq(claimable, total, 'claimable not total');
        assertEq(claimed, 0, 'claimed not 0');
        assertEq(timeRemaining, 0, 'timeRemaining not 0');

        address[] memory targets = new address[](4);
        targets[0] = address(treasury);
        targets[1] = address(permaStaker1);
        targets[2] = address(permaStaker2);
        targets[3] = FRAX_VEST_TARGET;
        for (uint256 i = 0; i < targets.length; i++) {
            vm.prank(targets[i]);
            vestManager.setClaimSettings(true, targets[i]);
        }
        uint256 claimedActual = vestManager.claim(address(treasury));
        (total, claimable, claimed, timeRemaining) = vestManager.getSingleVestData(address(treasury), 0);
        uint256 locked = total - claimed - claimable;
        uint256 vested = total - locked;
        assertEq(claimedActual, total / 5, 'Actual claimed not total / 5');
        assertEq(claimable, 0, 'claimable not 0');
        assertEq(locked, total * 4 / 5, 'locked not total * 4 / 5');
        assertEq(claimed, total / 5, 'claimed not total / 5');
        assertEq(vested, claimed, 'vested not == claimed');
        assertEq(timeRemaining, 4 * 365 days, 'timeRemaining not 4 years');

        claimedActual = vestManager.claim(FRAX_VEST_TARGET);
        (total, claimable, claimed, timeRemaining) = vestManager.getSingleVestData(FRAX_VEST_TARGET, 0);
        assertEq(claimedActual, total, 'Actual claimed not total');
        assertEq(claimable, 0, 'claimable not 0');
        assertEq(claimed, total, 'claimed not total');
        assertEq(claimed + claimable, total, 'vested not total');
        assertEq(timeRemaining, 0, 'timeRemaining not 0');

        skip(365 days);
        claimedActual = vestManager.claim(FRAX_VEST_TARGET);
        assertEq(claimedActual, 0, 'should be nothing more to claim');
    }

    function test_ClaimSettings() public {
        vm.prank(address(treasury));
        vestManager.claim(address(treasury));

        vm.prank(address(treasury));
        vestManager.setClaimSettings(false, address(this));

        vm.expectRevert("!authorized");
        vestManager.claim(address(treasury));

        skip(1 days);
        uint256 balanceBefore = govToken.balanceOf(address(this));
        vm.prank(address(treasury));
        vestManager.claim(address(treasury));
        assertGt(govToken.balanceOf(address(this)), balanceBefore);
    }


    function test_SetInitialParams() public {
        address[] memory targets = new address[](3);
        targets[0] = address(treasury);
        targets[1] = address(permaStaker1);
        targets[2] = address(permaStaker2);

        for (uint256 i = 0; i < uint256(type(VestManager.AllocationType).max); i++) {
            VestManager.AllocationType allocationType = VestManager.AllocationType(i);
            uint256 duration = vestManager.durationByType(allocationType);
            bytes32 merkleRoot = vestManager.merkleRootByType(allocationType);
            assertGt(duration, 0);
            if (
                allocationType == VestManager.AllocationType.AIRDROP_VICTIMS ||
                allocationType == VestManager.AllocationType.AIRDROP_TEAM
            ) {
                assertNotEq(merkleRoot, bytes32(0));
            }
            else {
                assertEq(merkleRoot, bytes32(0));
            }
            if (
                allocationType == VestManager.AllocationType.TREASURY ||
                allocationType == VestManager.AllocationType.PERMA_LOCK
            ) {
                (uint256 _duration, uint256 _amount, uint256 _claimed) = vestManager.userVests(targets[i], 0);
                assertGt(_duration, 0);
                assertGt(_amount, 0);
                assertEq(_claimed, 0);
            }
        }
        skip(1 weeks);
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(targets[i]);
            vestManager.claim(targets[i]);
            assertGt(govToken.balanceOf(targets[i]), 0);
        }
        
        // Check redemption ratio and allocation percentages
        uint expectedRedemptionRatio = (
            vestManager.allocationByType(VestManager.AllocationType.REDEMPTIONS) 
            * 1e18 
            / maxRedeemable
        );
        assertEq(expectedRedemptionRatio, vestManager.redemptionRatio());
        console.log('Redemption ratio: ', vestManager.redemptionRatio());
    }

    function test_AirdropClaim() public {
        assertNotEq(address(vestManager), address(0));
        (address[] memory users, uint256[] memory amounts, bytes32[][] memory proofs) = getSampleMerkleClaimData();
        
        assertNotEq(
            vestManager.merkleRootByType(VestManager.AllocationType.AIRDROP_TEAM), 
            bytes32(0),
            "AIRDROP_TEAM root not set"
        );
        assertNotEq(
            vestManager.merkleRootByType(VestManager.AllocationType.AIRDROP_VICTIMS), 
            bytes32(0),
            "AIRDROP_VICTIMS root not set"
        );
        assertEq(
            vestManager.merkleRootByType(VestManager.AllocationType.AIRDROP_LOCK_PENALTY), 
            bytes32(0),
            "AIRDROP_LOCK_PENALTY root unexpectedly set on init"
        );
        for (uint256 i = 0; i < proofs.length; i++) {
            vm.startPrank(users[i]);
            vestManager.merkleClaim(
                users[i],
                users[i],
                amounts[i],
                VestManager.AllocationType.AIRDROP_VICTIMS,
                proofs[i],
                i
            );
            vm.expectRevert("already claimed");
            vestManager.merkleClaim(
                users[i],
                users[i],
                amounts[i],
                VestManager.AllocationType.AIRDROP_VICTIMS,
                proofs[i],
                i
            );
            vm.expectRevert("root not set");
            vestManager.merkleClaim(
                users[i],
                users[i],
                amounts[i],
                VestManager.AllocationType.AIRDROP_LOCK_PENALTY,
                proofs[i],
                i
            );
            vm.stopPrank();
        }

        bytes32 sampleRoot = vestManager.merkleRootByType(VestManager.AllocationType.AIRDROP_TEAM);
        vm.startPrank(address(core));
        vestManager.setLockPenaltyMerkleRoot(sampleRoot, 1e18);
        vm.expectRevert("root already set");
        vestManager.setLockPenaltyMerkleRoot(sampleRoot, 1e18);
        vm.stopPrank();
        
        // Now we make sure users can claims from the final root
        for (uint256 i = 0; i < proofs.length; i++) {
            vm.startPrank(users[i]);
            vestManager.merkleClaim(
                users[i],
                users[i],
                amounts[i],
                VestManager.AllocationType.AIRDROP_LOCK_PENALTY,
                proofs[i],
                i
            );
            vm.stopPrank();
        }
    }

    function test_CannotClaimAirdropWithWrongProof() public {
        assertNotEq(address(vestManager), address(0));
        (address[] memory users, uint256[] memory amounts, bytes32[][] memory proofs) = getSampleMerkleClaimData();
        
        for (uint256 i = 0; i < proofs.length; i++) {
            vm.startPrank(users[i]);
            vm.expectRevert("invalid proof");
            uint256 wrongIndex = i + 1;
            if (wrongIndex >= proofs[i].length) wrongIndex = i - 1;
            vestManager.merkleClaim(
                users[i],
                users[i],
                amounts[i],
                VestManager.AllocationType.AIRDROP_TEAM,
                proofs[i],
                wrongIndex // WRONG INDEX
            );

            bytes32[] memory badProof;
            if (i >= proofs.length - 1) badProof = proofs[i-1];
            else badProof = proofs[i+1];
            vm.expectRevert("invalid proof");
            vestManager.merkleClaim(
                users[i],
                users[i],
                amounts[i],
                VestManager.AllocationType.AIRDROP_TEAM,
                badProof, // WRONG PROOF
                i
            );

            address wrongUser;
            vm.expectRevert("!CallerOrDelegated");
            vestManager.merkleClaim(
                wrongUser,
                users[i],
                amounts[i],
                VestManager.AllocationType.AIRDROP_TEAM,
                proofs[i],
                i
            );
            vm.stopPrank();
        }
    }

    function test_Redemption() public {
        vm.expectRevert("invalid token");
        vestManager.redeem(address(govToken), address(this), 1e18);

        uint256 redemptionRatio = vestManager.redemptionRatio();
        address[] memory tokens = new address[](3);
        tokens[0] = address(vestManager.prisma());
        tokens[1] = address(vestManager.yprisma());
        tokens[2] = address(vestManager.cvxprisma());
        uint256 totalUserGain = 0;
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 amount = 100e18;
            console.log('Dealing token... ', tokens[i]);
            deal(tokens[i], address(this), amount);
            IERC20(tokens[i]).approve(address(vestManager), amount);
            vestManager.redeem(tokens[i], address(this), amount);
            // Get data for the vest that was just created
            (
                uint256 _total,
                uint256 _claimable,
                uint256 _claimed,
                uint256 _timeRemaining
            ) = vestManager.getSingleVestData(address(this), 0);

            // Check that the amount is correct
            totalUserGain += amount * redemptionRatio / 1e18;
            assertEq(totalUserGain, _total);
            assertEq(vestManager.numAccountVests(address(this)), 1);
        }

        skip(1 weeks);
        for (uint256 i = 0; i < tokens.length; i++) {
            vm.startPrank(address(this));
            vestManager.claim(address(this));
            vm.stopPrank();
        }
    }

    function getSampleMerkleClaimData() public pure returns (address[] memory users, uint256[] memory amounts, bytes32[][] memory proofs) {
        users = new address[](3);
        amounts = new uint256[](3);
        proofs = new bytes32[][](3);

        // Example data from your JSON file
        users[0] = 0x46a83dC1a264Bff133dB887023d2884167094837;
        amounts[0] = 4903005963692896772161536;
        proofs[0] = new bytes32[](5);
        proofs[0][0] = 0x0034dc482e290250c7b0a532700e18918269c66b4d03a6855ed486c00d3cf9ef;
        proofs[0][1] = 0xdf9ea50af697b8a23e4a0a81780a3a87eb956d8324f4594e668192977f213238;
        proofs[0][2] = 0x504eb35476a7a64c378c228c51ca28ceb4d6b568a382d5ca5c941fbc42700835;
        proofs[0][3] = 0x8e14177290ecff25415e54d5ed6ede02ef08f64d9bde9687b9fa7b9642d56e9e;
        proofs[0][4] = 0x3ef1a0430cebb90c18513e5af6edbb4e511d7d40e1ced214963cb42870ed0b8c;

        users[1] = 0xb20b384C2F958f2100E14C5048922613F937674A;
        amounts[1] = 2054106109690402576531456;
        proofs[1] = new bytes32[](5);
        proofs[1][0] = 0x438be342e52ba933e6f3aaeed9b8e29f52f5a47ae491dbfca5a4a525d8663df5;
        proofs[1][1] = 0x0970829dec67afd767644142dc22b1ae45237a719591e37755406cbaac2e3165;
        proofs[1][2] = 0xe14c7f170b2316ef588bb377424eac8e44e9e1c93f0fd606a4e37926f7f790cc;
        proofs[1][3] = 0x8e14177290ecff25415e54d5ed6ede02ef08f64d9bde9687b9fa7b9642d56e9e;
        proofs[1][4] = 0x3ef1a0430cebb90c18513e5af6edbb4e511d7d40e1ced214963cb42870ed0b8c;

        users[2] = 0xD60cd4AD7A2D6bF4eC9fccbCAeec769b52726dfd;
        amounts[2] = 1517100053696941217808384;
        proofs[2] = new bytes32[](5);
        proofs[2][0] = 0x9d6ee2cacdb95d4b802326614bef1f853d37cf48afec52e1b74d01df2eea45d0;
        proofs[2][1] = 0xc025cf4f8e2cd25af6209ef3f0de66754f388e98873778417046b3f461742a91;
        proofs[2][2] = 0xc82eab709c3962ded202a48d010dfaa80ffb65dca8d1ec1f802823c4604c4ffa;
        proofs[2][3] = 0x8c398a265ad9d4df691bf984f2a67c4b087274d2332cb0f41a3ccc4fee2465e9;
        proofs[2][4] = 0xc93c4bd617a7d12786e97aa9b3433c6370426dfda54b4c6b9ca64cd796b367b3;
    }

    function getAllocationTypeName(VestManager.AllocationType allocationType) internal pure returns (string memory) {
        if (allocationType == VestManager.AllocationType.TREASURY) return "TREASURY";
        if (allocationType == VestManager.AllocationType.PERMA_LOCK) return "PERMA_LOCK";
        if (allocationType == VestManager.AllocationType.LICENSING) return "LICENSING";
        if (allocationType == VestManager.AllocationType.REDEMPTIONS) return "REDEMPTIONS";
        if (allocationType == VestManager.AllocationType.AIRDROP_TEAM) return "AIRDROP_TEAM";
        if (allocationType == VestManager.AllocationType.AIRDROP_VICTIMS) return "AIRDROP_VICTIMS";
        if (allocationType == VestManager.AllocationType.AIRDROP_LOCK_PENALTY) return "AIRDROP_LOCK_PENALTY";
        return "UNKNOWN";
    }

    function test_CannotReinitializeParams() public {
        VestManagerInitParams.InitParams memory params = VestManagerInitParams.getInitParams(
            address(permaStaker1),
            address(permaStaker2),
            address(treasury)
        );
        vm.prank(address(core));
        vm.expectRevert("params already set");
        vestManager.setInitializationParams(
            params.maxRedeemable,      // _maxRedeemable
            params.merkleRoots,
            params.nonUserTargets,
            params.durations,
            params.allocPercentages
        );
    }

    function test_PermaStakerCannotCallVestManager() public {
        bytes memory data = abi.encodeWithSelector(
            vestManager.setClaimSettings.selector,
            true,           // _allowPermissionlessClaims
            address(this)   // _recipient
        );
        vm.startPrank(permaStaker1.owner());
        vm.expectRevert("target not allowed");
        permaStaker1.execute(address(vestManager), data);
        vm.expectRevert("target not allowed");
        permaStaker1.safeExecute(address(vestManager), data);
        vm.stopPrank();
    }

    function test_ClaimWithCallback() public {
        createVest(100_000e18);
        uint256 startBalance = govToken.balanceOf(address(this));
        uint256 startStakerBalance = staker.balanceOf(address(this));
        uint256 claimed = vestManager.claimWithCallback(address(this), address(this), address(autoStakeCallback));
        assertEq(govToken.balanceOf(address(this)), startBalance);
        assertEq(staker.balanceOf(address(this)), startStakerBalance + claimed);
    }

    function createVest(uint256 amount) public {
        address prisma = address(vestManager.prisma());
        deal(prisma, address(this), amount);
        IERC20(prisma).approve(address(vestManager), amount);
        vestManager.redeem(prisma, address(this), amount);
        // Get data for the vest that was just created
        (
            uint256 _total,
            uint256 _claimable,
            uint256 _claimed,
            uint256 _timeRemaining
        ) = vestManager.getSingleVestData(address(this), 0);
        assertGe(vestManager.numAccountVests(address(this)), 1);
        assertGt(_total, 0);
    }
}