// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Mainnet } from "src/Constants.sol";
import { ICurveVoting } from "src/interfaces/curve/ICurveVoting.sol";

abstract contract CurveVoteHelper {
    function buildOwnershipScript(address target, bytes memory data) internal pure returns (bytes memory script) {
        return buildScript(Mainnet.CURVE_OWNERSHIP_AGENT, target, data);
    }

    function buildScript(address agent, address target, bytes memory data) internal pure returns (bytes memory script) {
        bytes memory action = abi.encodeWithSelector(ICurveVoting.execute.selector, target, 0, data);
        script = abi.encodePacked(uint32(1), agent, uint32(action.length), action);
    }
}
