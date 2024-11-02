pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import { Setup } from "../utils/Setup.sol";
import { Claimer } from "../../../src/dao/tge/Claimer.sol";


contract ClaimerTest is Setup {
    function setUp() public override {
        super.setUp();
        
        console.log('xxx',address(vesting));
        console.log('yyy',address(vesting.token()));
        claimer = new Claimer(
            address(vesting),
            address(prismaToken),
            150_000_000e18,
            getMerkleRoots(),
            [uint256(10000), uint256(0), uint256(0), uint256(0), uint256(0)]
        );

        vm.prank(address(core));
        vesting.setClaimer(address(claimer));
    }

    function test_AirdropClaim() public {
        assertNotEq(address(claimer), address(0));
        (address[] memory users, uint256[] memory amounts, bytes32[][] memory proofs) = getSampleData();
        
        for (uint256 i = 0; i < proofs.length; i++) {
            vm.prank(users[i]);
            claimer.merkleClaim(
                users[i],
                users[i],
                amounts[i],
                Claimer.MerkleClaimType.COMPENSATION,
                proofs[i],
                i + 1
            );
        }
    }

    function getMerkleRoots() public pure returns (bytes32[3] memory roots) {
        roots[0] = 0xc6c10c31fd61d6c77896fc0138839ff0c99a85f355ec704bda15e46ee804a958;
        roots[1] = 0xc6c10c31fd61d6c77896fc0138839ff0c99a85f355ec704bda15e46ee804a958;
        roots[2] = 0xc6c10c31fd61d6c77896fc0138839ff0c99a85f355ec704bda15e46ee804a958;
    }

    function getSampleData() public pure returns (address[] memory users, uint256[] memory amounts, bytes32[][] memory proofs) {
        users = new address[](3);
        amounts = new uint256[](3);
        proofs = new bytes32[][](3);

        // Example data from your JSON file
        users[0] = 0x254747CB22Df3DaA0aDF1b9a81697662AdA44CD5;
        amounts[0] = 1080000000000000000000;
        proofs[0] = new bytes32[](5);
        proofs[0][0] = 0x89327b954052e9fb205be0481b43c1ec140c57b409331d9614aa975880bcb7c9;
        proofs[0][1] = 0xdaa44fc4e14f39fcfc4353a6891f36d124402bf115fe6da0f83fc59b23e71dda;
        proofs[0][2] = 0x1daca70bd877c1e4cb75fc60d600d8393755a48d6195fee8876cb0a330d991cf;
        proofs[0][3] = 0x2096ff87aa31ffa7a17f62bb46c07a50866cbef1364ec418ed442dc8706ec510;
        proofs[0][4] = 0x0b8bac717691b6b3a5ddb46bfa2ba2033bd9ebd5cb0fc377d0c0bc0c66f95671;

        users[1] = 0xb20b384C2F958f2100E14C5048922613F937674A;
        amounts[1] = 68989057692307692307684;
        proofs[1] = new bytes32[](5);
        proofs[1][0] = 0x65c9a92f93132bce9eee273f05606ec2401f24582c7b4898202462ab5bb25c83;
        proofs[1][1] = 0xdaa44fc4e14f39fcfc4353a6891f36d124402bf115fe6da0f83fc59b23e71dda;
        proofs[1][2] = 0x1daca70bd877c1e4cb75fc60d600d8393755a48d6195fee8876cb0a330d991cf;
        proofs[1][3] = 0x2096ff87aa31ffa7a17f62bb46c07a50866cbef1364ec418ed442dc8706ec510;
        proofs[1][4] = 0x0b8bac717691b6b3a5ddb46bfa2ba2033bd9ebd5cb0fc377d0c0bc0c66f95671;

        users[2] = 0xD6CcAd20d688739349f0E4F3ae2ec69bC5039354;
        amounts[2] = 213000000000000000000;
        proofs[2] = new bytes32[](5);
        proofs[2][0] = 0xe2957697a1d2f245115257cfb1598fe7f8c9af93ac641b25f8ef7de1a331aed1;
        proofs[2][1] = 0x86df2c376408d4098b842b8789b3218aaf5aa649f648185c8f4046fa863e8528;
        proofs[2][2] = 0x1daca70bd877c1e4cb75fc60d600d8393755a48d6195fee8876cb0a330d991cf;
        proofs[2][3] = 0x2096ff87aa31ffa7a17f62bb46c07a50866cbef1364ec418ed442dc8706ec510;
        proofs[2][4] = 0x0b8bac717691b6b3a5ddb46bfa2ba2033bd9ebd5cb0fc377d0c0bc0c66f95671;
    }
}
