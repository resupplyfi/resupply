pragma solidity ^0.8.22;

// import "forge-std/Test.sol";
import { Setup } from "../utils/Setup.sol";
import { VestManager } from "../../../src/dao/tge/VestManager.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { console } from "../../../lib/forge-std/src/console.sol";
import { MockToken } from "../../mocks/MockToken.sol";

contract VestManagerTest is Setup {

    // Max amount of redeemable PRISMA/yPRISMA/cvxPRISMA
    uint256 maxRedeemable = 150_000_000e18;

    function setUp() public override {
        super.setUp();
        
        assertEq(vestManager.redemptionRatio(), 0);
        address prisma = address(vestManager.prisma());
        vm.expectRevert("ratio not set");
        vestManager.redeem(prisma, address(this), 1e18);

        vm.prank(address(core));
        vestManager.setInitializationParams(
            maxRedeemable,      // _maxRedeemable
            [
                bytes32(0x3adb010769f8a36c20d9ec03b89fe4d7f725c8ba133ce65faba53e18d13bf41f),
                bytes32(0x3adb010769f8a36c20d9ec03b89fe4d7f725c8ba133ce65faba53e18d13bf41f),
                bytes32(0) // We set this one later
            ],
            [   // _nonUserTargets
                address(treasury), 
                address(permaLocker1), // Convex
                address(permaLocker2)  // Yearn
            ],
            [   // _durations
                uint256(365 days),  // TREASURY
                uint256(365 days),  // PERMA_LOCKER1
                uint256(365 days),  // PERMA_LOCKER2
                uint256(365 days),  // REDEMPTIONS
                uint256(365 days),  // AIRDROP_TEAM
                uint256(365 days),  // AIRDROP_VICTIMS
                uint256(365 days)   // AIRDROP_LOCK_PENALTY
            ],
            [ // _allocPercentages
                uint256(1200),  // TREASURY
                uint256(2000),  // PERMA_LOCKER1 - Convex
                uint256(1000),  // PERMA_LOCKER2 - Yearn
                uint256(1500),  // REDEMPTIONS
                uint256(100),   // AIRDROP_TEAM
                uint256(200),   // AIRDROP_VICTIMS
                uint256(0),     // AIRDROP_LOCK_PENALTY
                uint256(4000)   // Emissions, first 5 years
            ]
        );
    }


    function test_SetInitialParams() public {
        address[] memory targets = new address[](3);
        targets[0] = address(treasury);
        targets[1] = address(permaLocker1);
        targets[2] = address(permaLocker2);

        for (uint256 i = 0; i < uint256(type(VestManager.AllocationType).max); i++) {
            VestManager.AllocationType allocationType = VestManager.AllocationType(i);
            uint256 duration = vestManager.durationByType(allocationType);
            uint256 allocation = vestManager.allocationByType(allocationType);
            bytes32 merkleRoot = vestManager.merkleRootByType(allocationType);
            assertGt(duration, 0);
            assertGt(allocation, 0);
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
                allocationType == VestManager.AllocationType.PERMA_LOCKER1 ||
                allocationType == VestManager.AllocationType.PERMA_LOCKER2
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
            vm.stopPrank();
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
        vestManager.setLockPenaltyMerkleRoot(sampleRoot);
        vm.expectRevert("root already set");
        vestManager.setLockPenaltyMerkleRoot(sampleRoot);
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
            vm.expectRevert("invalid proof");
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
                uint256 _claimable,
                uint256 _locked,
                uint256 _claimed,
                uint256 _vested
            ) = vestManager.getSingleVestData(address(this), 0);

            // Check that the amount is correct
            totalUserGain += amount * redemptionRatio / 1e18;
            assertEq(totalUserGain, _locked + _vested);
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
        if (allocationType == VestManager.AllocationType.PERMA_LOCKER1) return "PERMA_LOCKER1";
        if (allocationType == VestManager.AllocationType.PERMA_LOCKER2) return "PERMA_LOCKER2";
        if (allocationType == VestManager.AllocationType.REDEMPTIONS) return "REDEMPTIONS";
        if (allocationType == VestManager.AllocationType.AIRDROP_TEAM) return "AIRDROP_TEAM";
        if (allocationType == VestManager.AllocationType.AIRDROP_VICTIMS) return "AIRDROP_VICTIMS";
        if (allocationType == VestManager.AllocationType.AIRDROP_LOCK_PENALTY) return "AIRDROP_LOCK_PENALTY";
        return "UNKNOWN";
    }

    function test_CannotReinitializeParams() public {
        vm.prank(address(core));
        vm.expectRevert("params already set");
        vestManager.setInitializationParams(
            maxRedeemable,      // _maxRedeemable
            [
                bytes32(0x3adb010769f8a36c20d9ec03b89fe4d7f725c8ba133ce65faba53e18d13bf41f),
                bytes32(0x3adb010769f8a36c20d9ec03b89fe4d7f725c8ba133ce65faba53e18d13bf41f),
                bytes32(0) // We set this one later
            ],
            [   // _nonUserTargets
                address(treasury), 
                address(permaLocker1), // Convex
                address(permaLocker2)  // Yearn
            ],
            [   // _durations
                uint256(365 days),  // TREASURY
                uint256(365 days),  // PERMA_LOCKER1
                uint256(365 days),  // PERMA_LOCKER2
                uint256(365 days),  // REDEMPTIONS
                uint256(365 days),  // AIRDROP_TEAM
                uint256(365 days),  // AIRDROP_VICTIMS
                uint256(365 days)   // AIRDROP_LOCK_PENALTY
            ],
            [ // _allocPercentages
                uint256(1200),  // TREASURY
                uint256(2000),  // PERMA_LOCKER1 - Convex
                uint256(1000),  // PERMA_LOCKER2 - Yearn
                uint256(1500),  // REDEMPTIONS
                uint256(100),   // AIRDROP_TEAM
                uint256(200),   // AIRDROP_VICTIMS
                uint256(0),     // AIRDROP_LOCK_PENALTY
                uint256(4000)   // Emissions, first 5 years
            ]
        );
    }
}