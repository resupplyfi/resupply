// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol } from "src/Constants.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { ICore } from "src/interfaces/ICore.sol";
import { IAuthHook } from "src/interfaces/IAuthHook.sol";

struct PermissionUpdate {
    address caller;
    address target;
    bytes4 selector;
    bool enabled;
}

library PermissionHelper {
    function buildPermissionActions(
        ICore core,
        PermissionUpdate[] calldata updates
    ) external view returns (IVoter.Action[] memory actions) {
        actions = new IVoter.Action[](updates.length);
        
        for (uint256 i = 0; i < updates.length; i++) {
            PermissionUpdate calldata update = updates[i];
            
            // Validate current state matches expected state for the update
            (bool currentlyEnabled, ) = core.operatorPermissions(update.caller, update.target, update.selector);
            if (update.enabled) require(!currentlyEnabled, "Permission already enabled");
            else require(currentlyEnabled, "Permission not currently enabled");
            
            actions[i] = buildOperatorPermissionAction(
                update.caller,
                update.target, 
                update.selector,
                update.enabled
            );
        }
    }

    function buildOperatorPermissionAction(
        address caller,
        address target,
        bytes4 selector,
        bool enable
    ) internal pure returns (IVoter.Action memory action) {
        action = IVoter.Action({
            target: Protocol.CORE,
            data: abi.encodeWithSelector(
                ICore.setOperatorPermissions.selector,
                caller,
                target,
                selector,
                enable,
                address(0) // Auth Hook
            )
        });
    }

    function isPermissionEnabled(
        ICore core,
        address caller, 
        address target, 
        bytes4 selector
    ) external view returns (bool enabled) {
        (enabled, ) = core.operatorPermissions(caller, target, selector);
    }
}
