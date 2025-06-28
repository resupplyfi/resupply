pragma solidity 0.8.28;

import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { Protocol } from "src/Constants.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { TenderlyHelper } from "script/utils/TenderlyHelper.sol";
import { console } from "lib/forge-std/src/console.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";

interface IPermastakerOperator {
    function safeExecute(address target, bytes calldata data) external;
    function createNewProposal(IVoter.Action[] calldata actions, string calldata description) external;
}

contract ProposeVote is TenderlyHelper, BaseAction {
    uint256 public constant AMOUNT = 6_000_000e18;
    address public constant deployer = 0x4444AAAACDBa5580282365e25b16309Bd770ce4a;
    address public constant voter = 0x11111111063874cE8dC6232cb5C1C849359476E6;
    address public constant badDebtPayer = 0x024b682c064c287ea5ca7b6CB2c038d42f34EA0D;
    address public constant stablecoin = Protocol.STABLECOIN;
    address public constant insurancePool = Protocol.INSURANCE_POOL;
    address public constant registry = Protocol.REGISTRY;
    address public constant pair = 0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6;
    IPermastakerOperator public constant PERMA_STAKER_OPERATOR = IPermastakerOperator(0x3419b3FfF84b5FBF6Eec061bA3f9b72809c955Bf);

    function run() public isBatch(deployer) {
        deployMode = DeployMode.FORK;

        proposeVote();

        if (deployMode == DeployMode.PRODUCTION) executeBatch(true);
    }

    function proposeVote() public {
        address currentLiquidationHandler = IResupplyRegistry(registry).liquidationHandler();
        
        // Action 1: Set liquidation handler to core
        bytes memory setLiquidationHandlerCalldata = abi.encodeWithSignature(
            "setLiquidationHandler(address)",
            address(core)
        );
        // Action 2: Burn assets from insurance pool
        bytes memory burnAssetsCalldata = abi.encodeWithSignature(
            "burnAssets(uint256)",
            AMOUNT
        );
        // Action 3: Mint stablecoin to core
        bytes memory mintCalldata = abi.encodeWithSignature(
            "mint(address,uint256)",
            address(core),
            AMOUNT
        );
        // Action 4: Approve BadDebtPayer to spend stablecoin
        bytes memory approveCalldata = abi.encodeWithSignature(
            "approve(address,uint256)",
            address(badDebtPayer),
            AMOUNT
        );
        // Action 5: Call payBadDebt on BadDebtPayer
        bytes memory payBadDebtCalldata = abi.encodeWithSignature(
            "payBadDebt(uint256)",
            AMOUNT
        );        
        // Action 6: Set liquidation handler back to original
        bytes memory restoreLiquidationHandlerCalldata = abi.encodeWithSignature(
            "setLiquidationHandler(address)",
            currentLiquidationHandler
        );
        // Action 7: Reset IP withdraw timers
        bytes memory resetIpWithdrawTimersCalldata = abi.encodeWithSignature(
            "setWithdrawTimers(uint256,uint256)",
            7 days + 1 seconds,
            3 days + 1 seconds
        );
        // Action 8: Set voter voting period to 7 days
        bytes memory setVoterTimeCalldata = abi.encodeWithSignature(
            "setVotingPeriod(uint256)",
            7 days
        );
        // Action 9: Set voter execution delay to 1 day
        bytes memory setExecutionDelayCalldata = abi.encodeWithSignature(
            "setExecutionDelay(uint256)",
            1 days
        );

        IVoter.Action[] memory actions = new IVoter.Action[](9);
        actions[0] = IVoter.Action({
            target: address(registry),
            data: setLiquidationHandlerCalldata
        });
        actions[1] = IVoter.Action({
            target: address(insurancePool),
            data: burnAssetsCalldata
        });
        actions[2] = IVoter.Action({
            target: address(stablecoin),
            data: mintCalldata
        });
        actions[3] = IVoter.Action({
            target: address(stablecoin),
            data: approveCalldata
        });
        actions[4] = IVoter.Action({
            target: address(badDebtPayer),
            data: payBadDebtCalldata
        });
        actions[5] = IVoter.Action({
            target: address(registry),
            data: restoreLiquidationHandlerCalldata
        });
        actions[6] = IVoter.Action({
            target: address(insurancePool),
            data: resetIpWithdrawTimersCalldata
        });
        actions[7] = IVoter.Action({
            target: address(voter),
            data: setVoterTimeCalldata
        });
        actions[8] = IVoter.Action({
            target: address(voter),
            data: setExecutionDelayCalldata
        });

        addToBatch(
            address(PERMA_STAKER_OPERATOR),
            abi.encodeWithSelector(
                IPermastakerOperator.createNewProposal.selector,
                actions,
                "Pay bad debt through governance"
            )
        );
    }
}