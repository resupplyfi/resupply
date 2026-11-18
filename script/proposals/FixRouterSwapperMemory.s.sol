// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Script } from "lib/forge-std/src/Script.sol";
import { console } from "lib/forge-std/src/console.sol";
import { Protocol } from "src/Constants.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IRouterSwapper } from "src/interfaces/IRouterSwapper.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { RouterSwapper } from "src/protocol/swappers/RouterSwapper.sol";

contract FixRouterSwapperMemory is Script {
    IVoter public constant VOTER = IVoter(Protocol.VOTER);
    IResupplyRegistry public constant REGISTRY = IResupplyRegistry(Protocol.REGISTRY);

    address public constant OLD_ENSO_SWAPPER = 0x181c98113ce60BA75A0f72d8901Eb17e5065043D;
    address public constant OLD_LIFI_SWAPPER = 0x597Db76794c75E588D3a70534FB34B7780941fCe;
    string public constant DESCRIPTION = "Migrate Enso and LI.FI swappers to gas-optimized versions";

    /// @dev Run DeployRouterSwappers to deploy and initialize approvals, then
    ///      verify both deployments and pass their addresses to run(address,address).
    ///      Coordinate pair registration during voting: this proposal snapshots the pair
    ///      list and defaults at creation. Before execution, refresh replacement approvals,
    ///      re-simulate, and cover any newly added pairs or changed defaults.
    function run(address ensoSwapper, address lifiSwapper) public {
        IVoter.Action[] memory actions = buildProposalCalldata(ensoSwapper, lifiSwapper);
        printCallData(actions);

        vm.startBroadcast();
        (, address proposer,) = vm.readCallers();
        uint256 proposalId = VOTER.createNewProposal(proposer, actions, DESCRIPTION);
        vm.stopBroadcast();

        console.log("Proposal created by:", proposer);
        console.log("Proposal ID:", proposalId);
    }

    function buildProposalCalldata(address ensoSwapper, address lifiSwapper) public view returns (IVoter.Action[] memory actions) {
        address[2] memory oldSwappers = [OLD_ENSO_SWAPPER, OLD_LIFI_SWAPPER];
        address[2] memory newSwappers = [ensoSwapper, lifiSwapper];
        string[2] memory keys = [string("SWAPPER_ENSO"), "SWAPPER_LIFI"];
        address[] memory registeredPairs = REGISTRY.getAllPairAddresses();
        address[] memory defaults = buildDefaultSwappers(ensoSwapper, lifiSwapper);
        for (uint256 i; i < oldSwappers.length; i++) {
            address oldSwapper = oldSwappers[i];
            address newSwapper = newSwappers[i];
            require(REGISTRY.getAddress(keys[i]) == oldSwapper, "Current swapper changed");
            require(!IRouterSwapper(oldSwapper).approvalsRevoked(), "Current swapper revoked");
            require(newSwapper != oldSwapper && newSwapper.code.length > 0, "Invalid replacement");
            require(RouterSwapper(newSwapper).owner() == Protocol.CORE, "Wrong replacement owner");
            require(IRouterSwapper(newSwapper).router() == IRouterSwapper(oldSwapper).router(), "Wrong replacement router");
            require(!IRouterSwapper(newSwapper).approvalsRevoked(), "Replacement revoked");
            require(!IRouterSwapper(newSwapper).canUpdateApprovals(), "Replacement approvals incomplete");
        }

        actions = new IVoter.Action[](5 + registeredPairs.length * 4);
        uint256 index;

        // Action 1: Revoke old Enso router approvals.
        actions[index++] = IVoter.Action({
            target: OLD_ENSO_SWAPPER,
            data: abi.encodeWithSelector(IRouterSwapper.revokeApprovals.selector)
        });

        // Action 2: Revoke old LI.FI router approvals.
        actions[index++] = IVoter.Action({
            target: OLD_LIFI_SWAPPER,
            data: abi.encodeWithSelector(IRouterSwapper.revokeApprovals.selector)
        });

        // Action 3: Register the replacement Enso swapper.
        actions[index++] = IVoter.Action({
            target: Protocol.REGISTRY,
            data: abi.encodeWithSelector(
                IResupplyRegistry.setAddress.selector,
                "SWAPPER_ENSO",
                ensoSwapper
            )
        });

        // Action 4: Register the replacement LI.FI swapper.
        actions[index++] = IVoter.Action({
            target: Protocol.REGISTRY,
            data: abi.encodeWithSelector(
                IResupplyRegistry.setAddress.selector,
                "SWAPPER_LIFI",
                lifiSwapper
            )
        });

        // Action 5: Set replacement defaults for future pairs, preserving unrelated swappers.
        actions[index++] = IVoter.Action({
            target: Protocol.REGISTRY,
            data: abi.encodeWithSelector(
                IResupplyRegistry.setDefaultSwappers.selector,
                defaults
            )
        });

        for (uint256 j; j < registeredPairs.length; j++) {
            // Action: Disable the old Enso swapper on this pair.
            actions[index++] = IVoter.Action({
                target: registeredPairs[j],
                data: abi.encodeWithSelector(
                    IResupplyPair.setSwapper.selector,
                    OLD_ENSO_SWAPPER,
                    false // approved
                )
            });

            // Action: Enable the replacement Enso swapper on this pair.
            actions[index++] = IVoter.Action({
                target: registeredPairs[j],
                data: abi.encodeWithSelector(
                    IResupplyPair.setSwapper.selector,
                    ensoSwapper,
                    true // approved
                )
            });

            // Action: Disable the old LI.FI swapper on this pair.
            actions[index++] = IVoter.Action({
                target: registeredPairs[j],
                data: abi.encodeWithSelector(
                    IResupplyPair.setSwapper.selector,
                    OLD_LIFI_SWAPPER,
                    false // approved
                )
            });

            // Action: Enable the replacement LI.FI swapper on this pair.
            actions[index++] = IVoter.Action({
                target: registeredPairs[j],
                data: abi.encodeWithSelector(
                    IResupplyPair.setSwapper.selector,
                    lifiSwapper,
                    true // approved
                )
            });
        }
    }

    function buildDefaultSwappers(address ensoSwapper, address lifiSwapper) public view returns (address[] memory defaults) {
        uint256 count;
        while (true) {
            try REGISTRY.defaultSwappers(count) returns (address) {
                count++;
            } catch {
                break;
            }
        }

        defaults = new address[](count);
        uint256 replaced;
        for (uint256 i; i < count; i++) {
            address current = REGISTRY.defaultSwappers(i);
            if (current == OLD_ENSO_SWAPPER) {
                defaults[i] = ensoSwapper;
                replaced |= 1;
            } else if (current == OLD_LIFI_SWAPPER) {
                defaults[i] = lifiSwapper;
                replaced |= 2;
            } else {
                defaults[i] = current;
            }
        }
        require(replaced == 3, "Current default swappers missing");
    }

    function printCallData(IVoter.Action[] memory actions) public view {
        for (uint256 i; i < actions.length; i++) {
            console.log("Action", i + 1);
            console.log(actions[i].target);
            console.logBytes(actions[i].data);
            console.log("--------------------------------");
        }
    }
}
