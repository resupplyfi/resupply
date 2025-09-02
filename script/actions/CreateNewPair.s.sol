pragma solidity 0.8.28;

import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { Protocol, Mainnet } from "src/Constants.sol";
import { console } from "lib/forge-std/src/console.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { BaseProposal } from "script/proposals/BaseProposal.sol";
import { IResupplyPairDeployer } from "src/interfaces/IResupplyPairDeployer.sol";

contract CreateNewPair is BaseAction {
    uint256 public constant MAX_DISTRIBUTION_PER_SECOND_PER_ASSET = uint256(2e17) / 365 days; // 20% apr max distribution rate;
    uint256 public constant PROTOCOL_ID = Protocol.PROTOCOL_ID_CURVE;
    address public constant COLLATERAL = 0x7430f11Eeb64a4ce50C8f92177485d34C48DA72c;
    address public constant STAKING = PROTOCOL_ID == Protocol.PROTOCOL_ID_CURVE ? Mainnet.CONVEX_BOOSTER : address(0);
    uint256 public constant STAKING_ID = 483;

    function run() public isBatch(Protocol.DEPLOYER) {
        deployMode = DeployMode.FORK;

        address pair = pairDeployer.predictPairAddress(
            PROTOCOL_ID,
            COLLATERAL,
            STAKING,
            STAKING_ID
        );
        console.log("pair deployed at", pair);

        addToBatch(
            address(pairDeployer),
            abi.encodeWithSelector(
                pairDeployer.deployWithDefaultConfig.selector,
                PROTOCOL_ID,
                COLLATERAL,
                STAKING,
                STAKING_ID
            )
        );

        if (deployMode == DeployMode.PRODUCTION) {
            executeBatch(true);
        }
    }
}