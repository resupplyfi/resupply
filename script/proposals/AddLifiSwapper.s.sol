// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol } from "src/Constants.sol";
import { BaseProposal } from "script/proposals/BaseProposal.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { ISwapperLifi } from "src/interfaces/ISwapperLifi.sol";
import { console } from "lib/forge-std/src/console.sol";

contract AddLifiSwapper is BaseProposal {
    string public constant REGISTRY_KEY = "SWAPPER_LIFI";
    address public constant lifiSwapper = 0xd654ea19E90c593071b50EAF105F12e5fE42841B;

    function run() public isBatch(deployer) {
        deployMode = DeployMode.FORK;

        IVoter.Action[] memory data = buildProposalCalldata();
        proposeVote(data, "Configure LI.FI swapper");

        if (deployMode == DeployMode.PRODUCTION) {
            require(lifiSwapper.code.length > 0, "LI.FI swapper not deployed");
            executeBatch(true);
        }
    }

    function buildProposalCalldata() public override returns (IVoter.Action[] memory actions) {
        address[] memory defaultSwappers = buildDefaultSwappers(lifiSwapper);
        address[] memory registeredPairs = registry.getAllPairAddresses();

        actions = new IVoter.Action[](registeredPairs.length + 4);

        // Update token approvals
        actions[0] = IVoter.Action({ target: lifiSwapper, data: abi.encodeWithSelector(ISwapperLifi.updateApprovals.selector) });

        // Set registry key `SWAPPER_LIFI`
        actions[1] = IVoter.Action({ target: address(registry), data: abi.encodeWithSelector(IResupplyRegistry.setAddress.selector, REGISTRY_KEY, lifiSwapper) });

        // Add new swapper to default swappers
        actions[2] = IVoter.Action({ target: address(registry), data: abi.encodeWithSelector(IResupplyRegistry.setDefaultSwappers.selector, defaultSwappers) });

        // Set swapper on all pairs
        for (uint256 i = 0; i < registeredPairs.length; i++) {
            actions[i + 3] = IVoter.Action({ target: registeredPairs[i], data: abi.encodeWithSelector(IResupplyPair.setSwapper.selector, lifiSwapper, true) });
        }

        // Allow multisig to revoke approvals
        actions[registeredPairs.length + 3] = setOperatorPermission(Protocol.DEPLOYER, lifiSwapper, ISwapperLifi.revokeApprovals.selector, true);

        console.log("Number of actions:", actions.length);
        console.log("LI.FI swapper:", lifiSwapper);
    }

    function buildDefaultSwappers(address lifiSwapper) public view returns (address[] memory swappers) {
        address[] memory currentSwappers = getDefaultSwappers();
        bool hasLifiSwapper;
        for (uint256 i = 0; i < currentSwappers.length; i++) {
            if (currentSwappers[i] == lifiSwapper) hasLifiSwapper = true;
        }

        if (hasLifiSwapper) return currentSwappers;

        swappers = new address[](currentSwappers.length + 1);
        for (uint256 i = 0; i < currentSwappers.length; i++) {
            swappers[i] = currentSwappers[i];
        }
        swappers[currentSwappers.length] = lifiSwapper;
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

    function contains(address[] memory addresses, address target) public pure returns (bool) {
        for (uint256 i = 0; i < addresses.length; i++) {
            if (addresses[i] == target) return true;
        }
        return false;
    }
}
