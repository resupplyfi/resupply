// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol } from "src/Constants.sol";
import { InterestRateCalculatorV2 } from "src/protocol/InterestRateCalculatorV2.sol";
import { BaseAction } from "script/actions/dependencies/BaseAction.sol";

contract DeployIRCalcV2 is BaseAction {
    uint256 constant MINIMUM_RATE = 2e16 / uint256(365 days) * 2;
    uint256 constant RATE_RATIO_BASE = 5e17;
    uint256 constant RATE_RATIO_BASE_COLLATERAL = 625e15;
    uint256 constant RATE_RATIO_ADDITIONAL = 2e17;

    function run() public {
        vm.startBroadcast(loadPrivateKey());
        new InterestRateCalculatorV2(
            Protocol.CORE,
            MINIMUM_RATE,
            RATE_RATIO_BASE,
            RATE_RATIO_BASE_COLLATERAL,
            RATE_RATIO_ADDITIONAL,
            Protocol.PRICE_WATCHER
        );
        vm.stopBroadcast();
    }
}
