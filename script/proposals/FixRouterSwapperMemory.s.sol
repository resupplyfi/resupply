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
    string public constant DESCRIPTION = "Replace Enso and LI.FI swappers with a single-allocation route decoder";

    /// @dev Deploy and verify the patched RouterSwapper for each existing router first,
    ///      with Protocol.CORE as owner. Pass those addresses to run(address,address).
    ///      Coordinate pair registration during voting: this proposal snapshots the pair
    ///      list at creation. Re-simulate before execution and cover any newly added pairs.
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
        actions = new IVoter.Action[](7 + registeredPairs.length * 4);
        uint256 index;

        for (uint256 i; i < oldSwappers.length; i++) {
            address oldSwapper = oldSwappers[i];
            address newSwapper = newSwappers[i];
            require(REGISTRY.getAddress(keys[i]) == oldSwapper, "Current swapper changed");
            require(!IRouterSwapper(oldSwapper).approvalsRevoked(), "Current swapper revoked");
            require(newSwapper != oldSwapper && newSwapper.code.length > 0, "Invalid replacement");
            require(RouterSwapper(newSwapper).owner() == Protocol.CORE, "Wrong replacement owner");
            require(IRouterSwapper(newSwapper).router() == IRouterSwapper(oldSwapper).router(), "Wrong replacement router");
            require(!IRouterSwapper(newSwapper).approvalsRevoked(), "Replacement revoked");

            // Initialize collateral approvals on the replacement at execution time.
            actions[index++] = IVoter.Action({
                target: newSwapper,
                data: abi.encodeWithSelector(IRouterSwapper.updateApprovals.selector)
            });

            // Point the provider's registry key at the patched deployment.
            actions[index++] = IVoter.Action({
                target: Protocol.REGISTRY,
                data: abi.encodeWithSelector(
                    IResupplyRegistry.setAddress.selector,
                    keys[i], // provider registry key
                    newSwapper
                )
            });

            for (uint256 j; j < registeredPairs.length; j++) {
                // Replace the provider's allowed swapper on every existing pair.
                actions[index++] = IVoter.Action({
                    target: registeredPairs[j],
                    data: abi.encodeWithSelector(
                        IResupplyPair.setSwapper.selector,
                        oldSwapper,
                        false // approved
                    )
                });
                actions[index++] = IVoter.Action({
                    target: registeredPairs[j],
                    data: abi.encodeWithSelector(
                        IResupplyPair.setSwapper.selector,
                        newSwapper,
                        true // approved
                    )
                });
            }

            // Permanently disable the retired wrapper and clear its router allowances.
            actions[index++] = IVoter.Action({
                target: oldSwapper,
                data: abi.encodeWithSelector(IRouterSwapper.revokeApprovals.selector)
            });
        }

        // Future pairs inherit the replacements; unrelated defaults stay unchanged.
        actions[index] = IVoter.Action({
            target: Protocol.REGISTRY,
            data: abi.encodeWithSelector(
                IResupplyRegistry.setDefaultSwappers.selector,
                defaults
            )
        });
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
