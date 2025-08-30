// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol } from "src/Constants.sol";
import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { ICore } from "src/interfaces/ICore.sol";
import { console } from "lib/forge-std/src/console.sol";
import { IResupplyPairDeployer } from "src/interfaces/IResupplyPairDeployer.sol";

interface IPermastakerOperator {
    function safeExecute(address target, bytes calldata data) external;
    function createNewProposal(IVoter.Action[] calldata actions, string calldata description) external;
}

abstract contract BaseProposal is BaseAction {
    IResupplyRegistry public constant registry = IResupplyRegistry(Protocol.REGISTRY);
    ICore public constant _core = ICore(Protocol.CORE);
    IVoter public constant voter = IVoter(Protocol.VOTER);
    address public deployer = 0x4444AAAACDBa5580282365e25b16309Bd770ce4a;
    IResupplyPairDeployer public constant pairDeployer = IResupplyPairDeployer(Protocol.PAIR_DEPLOYER_V2);
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

    // Uses default config
    function getPairDeploymentAddressAndCallData(uint256 _protocolId, address _collateral, address _staking, uint256 _stakingId) public returns(address, bytes memory){
        address predictedAddress = pairDeployer.predictPairAddress(
            _protocolId,
            _collateral,
            _staking,
            _stakingId
        );
        bytes memory callData = abi.encodeWithSelector(
            pairDeployer.deployWithDefaultConfig.selector,
            _protocolId,
            _collateral,
            _staking,
            _stakingId
        );
        return (predictedAddress, callData);
    }

    function buildProposalCalldata() public virtual returns (IVoter.Action[] memory actions);
}