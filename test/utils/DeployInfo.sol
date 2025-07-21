// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ResupplyPairDeployer } from "../../src/protocol/ResupplyPairDeployer.sol";

library DeployInfo {
    function getDeployInfo() public pure returns(address[] memory, ResupplyPairDeployer.DeployInfo[] memory){
        address[] memory pairs = new address[](17);
        ResupplyPairDeployer.DeployInfo[] memory deployInfos = new ResupplyPairDeployer.DeployInfo[](17);
        
        // Pair 1: CurveLend crvUSD/sfrxUSD
        pairs[0] = 0xC5184cccf85b81EDdc661330acB3E41bd89F34A1;
        deployInfos[0] = ResupplyPairDeployer.DeployInfo({
            protocolId: 0,
            deployTime: 1741832327
        });
        
        // Pair 2: CurveLend crvUSD/sDOLA
        pairs[1] = 0x08064A8eEecf71203449228f3eaC65E462009fdF;
        deployInfos[1] = ResupplyPairDeployer.DeployInfo({
            protocolId: 0,
            deployTime: 1741832327
        });
        
        // Pair 3: CurveLend crvUSD/sUSDe
        pairs[2] = 0x39Ea8e7f44E9303A7441b1E1a4F5731F1028505C;
        deployInfos[2] = ResupplyPairDeployer.DeployInfo({
            protocolId: 0,
            deployTime: 1741832399
        });
        
        // Pair 4: CurveLend crvUSD/USDe
        pairs[3] = 0x3b037329Ff77B5863e6a3c844AD2a7506ABe5706;
        deployInfos[3] = ResupplyPairDeployer.DeployInfo({
            protocolId: 0,
            deployTime: 1741832399
        });
        
        // Pair 5: CurveLend crvUSD/tBTC
        pairs[4] = 0x22B12110f1479d5D6Fd53D0dA35482371fEB3c7e;
        deployInfos[4] = ResupplyPairDeployer.DeployInfo({
            protocolId: 0,
            deployTime: 1741832459
        });
        
        // Pair 6: CurveLend crvUSD/WBTC
        pairs[5] = 0x2d8ecd48b58e53972dBC54d8d0414002B41Abc9D;
        deployInfos[5] = ResupplyPairDeployer.DeployInfo({
            protocolId: 0,
            deployTime: 1741832459
        });
        
        // Pair 7: CurveLend crvUSD/WETH
        pairs[6] = 0xCF1deb0570c2f7dEe8C07A7e5FA2bd4b2B96520D;
        deployInfos[6] = ResupplyPairDeployer.DeployInfo({
            protocolId: 0,
            deployTime: 1741832495
        });
        
        // Pair 8: CurveLend crvUSD/wstETH
        pairs[7] = 0x4A7c64932d1ef0b4a2d430ea10184e3B87095E33;
        deployInfos[7] = ResupplyPairDeployer.DeployInfo({
            protocolId: 0,
            deployTime: 1741832495
        });
        
        // Pair 9: Fraxlend frxUSD/sfrxETH
        pairs[8] = 0x3F2b20b8E8Ce30bb52239d3dFADf826eCFE6A5f7;
        deployInfos[8] = ResupplyPairDeployer.DeployInfo({
            protocolId: 1,
            deployTime: 1741832591
        });
        
        // Pair 10: Fraxlend frxUSD/sUSDe
        pairs[9] = 0x212589B06EBBA4d89d9deFcc8DDc58D80E141EA0;
        deployInfos[9] = ResupplyPairDeployer.DeployInfo({
            protocolId: 1,
            deployTime: 1741832591
        });
        
        // Pair 11: Fraxlend frxUSD/WBTC
        pairs[10] = 0x55c49c707aA0Ad254F34a389a8dFd0d103894aDb;
        deployInfos[10] = ResupplyPairDeployer.DeployInfo({
            protocolId: 1,
            deployTime: 1741832639
        });
        
        // Pair 12: Fraxlend frxUSD/scrvUSD
        pairs[11] = 0x24CCBd9130ec24945916095eC54e9acC7382c864;
        deployInfos[11] = ResupplyPairDeployer.DeployInfo({
            protocolId: 1,
            deployTime: 1741832639
        });
        
        // Pair 13: Fraxlend frxUSD/WBTC (2nd instance)
        pairs[12] = 0xb5575Fe3d3b7877415A166001F67C2Df94D4e6c1;
        deployInfos[12] = ResupplyPairDeployer.DeployInfo({
            protocolId: 1,
            deployTime: 1742408603
        });
        
        // Pair 14: CurveLend crvUSD/sDOLA (2nd instance)
        pairs[13] = 0x27AB448a75d548ECfF73f8b4F36fCc9496768797;
        deployInfos[13] = ResupplyPairDeployer.DeployInfo({
            protocolId: 0,
            deployTime: 1744846547
        });
        
        // Pair 15: CurveLend crvUSD/sUSDS
        pairs[14] = 0x57E69699381a651Fb0BBDBB31888F5D655Bf3f06;
        deployInfos[14] = ResupplyPairDeployer.DeployInfo({
            protocolId: 0,
            deployTime: 1747422935
        });
        
        // Pair 16: CurveLend crvUSD/tBTC (2nd instance)
        pairs[15] = 0xF4A6113FbD71Ac1825751A6fe844A156f60C83EF;
        deployInfos[15] = ResupplyPairDeployer.DeployInfo({
            protocolId: 0,
            deployTime: 1747422935
        });
        
        // Pair 17: CurveLend crvUSD/wstUSR
        pairs[16] = 0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6;
        deployInfos[16] = ResupplyPairDeployer.DeployInfo({
            protocolId: 0,
            deployTime: 1750897127
        });
        
        return (pairs, deployInfos);
    }
}