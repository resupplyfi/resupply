// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol, Mainnet } from "src/Constants.sol";
import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { ICore } from "src/interfaces/ICore.sol";
import { console } from "lib/forge-std/src/console.sol";
import { IResupplyPairDeployer } from "src/interfaces/IResupplyPairDeployer.sol";
import { IPairAdder } from "src/interfaces/IPairAdder.sol";
import { IBorrowLimitController } from "src/interfaces/IBorrowLimitController.sol";
import { IConvexStaking } from "src/interfaces/convex/IConvexStaking.sol";

interface IPermastakerOperator {
    function safeExecute(address target, bytes calldata data) external;
    function createNewProposal(IVoter.Action[] calldata actions, string calldata description) external;
}

abstract contract BaseProposal is BaseAction {
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


    function getAddPairToRegistryCallData(address _pair) public returns(bytes memory){
        return abi.encodeWithSelector(
            IPairAdder.addPair.selector,
            _pair
        );
    }

    function getRampBorrowLimitCallData(address _pair, uint256 _newBorrowLimit, uint256 _endTime) public returns(bytes memory){
        return abi.encodeWithSelector(
            IBorrowLimitController.setPairBorrowLimitRamp.selector,
            _pair,
            _newBorrowLimit,
            _endTime
        );
    }

    function printCallData(IVoter.Action[] memory actions) public {
        for (uint256 i = 0; i < actions.length; i++) {
            console.log("Action", i+1);
            console.log(actions[i].target);
            console.logBytes(actions[i].data);
        }
    }

    function buildProposalCalldata() public virtual returns (IVoter.Action[] memory actions);
}