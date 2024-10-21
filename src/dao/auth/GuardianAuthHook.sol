pragma solidity ^0.8.22;

import {ICore} from "../../interfaces/ICore.sol";

contract GuardianAuthHook {
    bool public paused;

    function preHook(address operator, address target, bytes calldata data) external returns (bool) {
        ICore core = ICore(msg.sender);
        paused = core.isProtocolPaused();
        return true;
    }

    function postHook(bytes memory result, address operator, address target, bytes calldata data) external returns (bool) {
        ICore core = ICore(msg.sender);
        if (paused && !core.isProtocolPaused()) return false;
        return true;
    }
}
