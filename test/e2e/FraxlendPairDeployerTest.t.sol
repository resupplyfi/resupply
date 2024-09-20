// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "./BasePairTest.t.sol";
import "src/interfaces/IFraxlendPair.sol";
import "src/protocol/fraxlend/FraxlendPairDeployer.sol";

contract FraxlendPairDeployerTest is BasePairTest {
    function setUp() public {
        string memory _envKey = vm.envString("MAINNET_URL");
        vm.createSelectFork(_envKey, 16_474_174);
    }

    function testCanGlobalPause() public {
        defaultSetUp();
        deployFraxlendPublic(address(linearRateContract), 25 * ONE_PERCENT);
        startHoax(Constants.Mainnet.CIRCUIT_BREAKER_ADDRESS);
        address[] memory _addresses = deployer.getAllPairAddresses();
        deployer.globalPause(_addresses);
        for (uint256 i = 0; i < _addresses.length; i++) {
            FraxlendPair _fraxlendPair = FraxlendPair(_addresses[i]);

            assertTrue(_fraxlendPair.borrowLimit() == 0);
            // assertTrue(_fraxlendPair.depositLimit() == 0);
            assertTrue(_fraxlendPair.isWithdrawPaused());
            assertTrue(_fraxlendPair.isRepayPaused());
            assertTrue(_fraxlendPair.isLiquidatePaused());
            assertTrue(_fraxlendPair.isInterestPaused());
        }
    }
}
