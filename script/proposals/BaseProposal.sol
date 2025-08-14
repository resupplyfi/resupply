// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol } from "src/Constants.sol";
import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { ICore } from "src/interfaces/ICore.sol";
import { console } from "lib/forge-std/src/console.sol";

interface IPermastakerOperator {
    function safeExecute(address target, bytes calldata data) external;
    function createNewProposal(IVoter.Action[] calldata actions, string calldata description) external;
}

contract BaseProposal is BaseAction {
    IResupplyRegistry public constant registry = IResupplyRegistry(Protocol.REGISTRY);
    ICore public constant _core = ICore(Protocol.CORE);
    IVoter public constant voter = IVoter(Protocol.VOTER);
    address public deployer = 0x4444AAAACDBa5580282365e25b16309Bd770ce4a;
    IPermastakerOperator public constant PERMA_STAKER_OPERATOR = IPermastakerOperator(0x3419b3FfF84b5FBF6Eec061bA3f9b72809c955Bf);
    address public target;
    address[] public pairs;
    uint256 public numPairs;

    constructor() {
        target = address(PERMA_STAKER_OPERATOR);
        pairs = registry.getAllPairAddresses();
        numPairs = pairs.length;
    }
    
    function proposeVote(IVoter.Action[] memory actions, string memory description) public {
        addToBatch(
            address(target),
            abi.encodeWithSelector(
                IPermastakerOperator.createNewProposal.selector,
                actions,
                description
            )
        );
    }
}