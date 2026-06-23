// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { BaseProposal } from "script/proposals/BaseProposal.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IRouterSwapper } from "src/interfaces/IRouterSwapper.sol";
import { console } from "lib/forge-std/src/console.sol";

contract ReplaceRouterSwappers is BaseAction, BaseProposal {
    string public constant SWAPPER_ODOS_KEY = "SWAPPER_ODOS";
    string public constant SWAPPER_LIFI_KEY = "SWAPPER_LIFI";
    string public constant SWAPPER_ENSO_KEY = "SWAPPER_ENSO";

    address public constant oldOdosSwapper = 0x3Ae884D1a67650501278001FDa40DCa975D9194D;
    address public constant odosSwapper = 0x094739c1fE87aadB5C79bf5fa2901E9A5FEF3dB3;
    address public constant lifiSwapper = 0x597Db76794c75E588D3a70534FB34B7780941fCe;
    address public constant ensoSwapper = 0x181c98113ce60BA75A0f72d8901Eb17e5065043D;

    function run() public isBatch(deployer) {
        deployMode = DeployMode.FORK;

        IVoter.Action[] memory data = buildProposalCalldata();
        proposeVote(data, "Add new swappers to support additional meta DEX aggregators");

        if (deployMode == DeployMode.PRODUCTION) {
            require(odosSwapper.code.length > 0, "ODOS swapper not deployed");
            require(lifiSwapper.code.length > 0, "LI.FI swapper not deployed");
            require(ensoSwapper.code.length > 0, "ENSO swapper not deployed");
            executeBatch(true);
        }
    }

    function buildProposalCalldata() public override returns (IVoter.Action[] memory actions) {
        address[] memory registeredPairs = registry.getAllPairAddresses();
        address[] memory defaultSwappers = buildDefaultSwappers();

        actions = new IVoter.Action[](5 + registeredPairs.length * 4);
        uint256 index;

        // Revoke old ODOS router approvals before replacing the registry key.
        actions[index++] = IVoter.Action({
            target: oldOdosSwapper,
            data: abi.encodeWithSelector(IRouterSwapper.revokeApprovals.selector)
        });

        // Register provider-specific swapper keys
        actions[index++] = IVoter.Action({
            target: address(registry),
            data: abi.encodeWithSelector(
                IResupplyRegistry.setAddress.selector,
                SWAPPER_ODOS_KEY,
                odosSwapper
            )
        });
        actions[index++] = IVoter.Action({
            target: address(registry),
            data: abi.encodeWithSelector(
                IResupplyRegistry.setAddress.selector,
                SWAPPER_LIFI_KEY,
                lifiSwapper
            )
        });
        actions[index++] = IVoter.Action({
            target: address(registry),
            data: abi.encodeWithSelector(
                IResupplyRegistry.setAddress.selector,
                SWAPPER_ENSO_KEY,
                ensoSwapper
            )
        });

        // Configure defaults so future pairs include the provider set
        actions[index++] = IVoter.Action({
            target: address(registry),
            data: abi.encodeWithSelector(
                IResupplyRegistry.setDefaultSwappers.selector,
                defaultSwappers
            )
        });

        for (uint256 j = 0; j < registeredPairs.length; j++) {
            // Replace old ODOS and add all new provider swappers on existing pairs
            actions[index++] = IVoter.Action({
                target: registeredPairs[j],
                data: abi.encodeWithSelector(
                    IResupplyPair.setSwapper.selector,
                    oldOdosSwapper,
                    false
                )
            });
            actions[index++] = IVoter.Action({
                target: registeredPairs[j],
                data: abi.encodeWithSelector(
                    IResupplyPair.setSwapper.selector,
                    odosSwapper,
                    true
                )
            });
            actions[index++] = IVoter.Action({
                target: registeredPairs[j],
                data: abi.encodeWithSelector(
                    IResupplyPair.setSwapper.selector,
                    lifiSwapper,
                    true
                )
            });
            actions[index++] = IVoter.Action({
                target: registeredPairs[j],
                data: abi.encodeWithSelector(
                    IResupplyPair.setSwapper.selector,
                    ensoSwapper,
                    true
                )
            });
        }

        console.log("Number of actions:", actions.length);
        console.log("Old ODOS swapper:", oldOdosSwapper);
        console.log("Replacement ODOS swapper:", odosSwapper);
        console.log("LI.FI swapper:", lifiSwapper);
        console.log("ENSO swapper:", ensoSwapper);
    }

    function buildDefaultSwappers() public view returns (address[] memory swappers) {
        swappers = new address[](4);
        swappers[0] = registry.defaultSwappers(0);
        swappers[1] = odosSwapper;
        swappers[2] = lifiSwapper;
        swappers[3] = ensoSwapper;
    }

    function getDefaultSwappers() public view returns (address[] memory swappers) {
        uint256 count;
        while (true) {
            try registry.defaultSwappers(count) returns (address) {
                count++;
            } catch {
                break;
            }
        }

        swappers = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            swappers[i] = registry.defaultSwappers(i);
        }
    }

}
