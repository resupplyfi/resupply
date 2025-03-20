import { IVestManager } from "src/interfaces/IVestManager.sol";
import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { Protocol, VMConstants } from "script/protocol/ProtocolConstants.sol";
import { SimpleRewardStreamer } from "src/protocol/SimpleRewardStreamer.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { ICurvePool } from "src/interfaces/ICurvePool.sol";
import { console2 } from "forge-std/console2.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IFeeDepositController } from "src/interfaces/IFeeDepositController.sol";
import { ICore } from "src/interfaces/ICore.sol";
import { ITreasury } from "src/interfaces/ITreasury.sol";

contract LaunchSetup2 is BaseAction {
    address public constant deployer = Protocol.DEPLOYER;
    address public constant TREASURY = Protocol.TREASURY;
    IERC20 public constant rsup = IERC20(Protocol.GOV_TOKEN);
    IVestManager public constant vestManager = IVestManager(Protocol.VEST_MANAGER);
    ICurvePool public constant pool = ICurvePool(Protocol.WETH_RSUP_POOL);
    uint256 public constant DEFAULT_BORROW_LIMIT = 25_000_000e18;
    IFeeDepositController public constant feeDepositController = IFeeDepositController(Protocol.FEE_DEPOSIT_CONTROLLER);

    function run() public isBatch(deployer) {
        deployMode = DeployMode.FORK;
        setBorrowLimits();
        initVestManager();
        uint256 amount = updateVestSettingsAndClaim();
        createLP(amount);
        withdrawFees();
        setOperatorPermissions(); // Grant permissions to treasury functions
        if (deployMode == DeployMode.PRODUCTION) executeBatch(true);
    }
        
    function setBorrowLimits() public {
        address[] memory pairs = getPairs();
        for (uint256 i = 0; i < pairs.length; i++) {
            uint256 limit = DEFAULT_BORROW_LIMIT;

            // Overwrite default limit for select pairs
            if (pairs[i] == address(Protocol.PAIR_FRAXLEND_WBTC_FRXUSD_DEPRECATED)) continue;
            if (pairs[i] == address(Protocol.PAIR_CURVELEND_TBTC_CRVUSD_DEPRECATED)) continue;
            if (pairs[i] == address(Protocol.PAIR_CURVELEND_SFRXUSD_CRVUSD)) limit = 50_000_000e18;
            else if (pairs[i] == address(Protocol.PAIR_FRAXLEND_SCRVUSD_FRXUSD)) limit = 50_000_000e18;
            else if (pairs[i] == address(Protocol.PAIR_FRAXLEND_SFRXETH_FRXUSD)) limit = 50_000_000e18;
            else if (pairs[i] == address(Protocol.PAIR_CURVELEND_SDOLA_CRVUSD)) limit = 10_000_000e18;
            else if (
                pairs[i] == address(Protocol.PAIR_FRAXLEND_WBTC_FRXUSD) ||
                pairs[i] == address(Protocol.PAIR_CURVELEND_WBTC_CRVUSD) ||
                pairs[i] == address(Protocol.PAIR_CURVELEND_WETH_CRVUSD) ||
                pairs[i] == address(Protocol.PAIR_CURVELEND_WSTETH_CRVUSD)
            ) limit = 100_000_000e18;

            _executeCore(pairs[i], abi.encodeWithSelector(IResupplyPair.setBorrowLimit.selector, limit));
        }
    }

    function createLP(uint256 amount) public {
        address token0 = pool.coins(0);
        address token1 = pool.coins(1);
        deal(token0, Protocol.TREASURY, 100e18);
        uint256 price = pool.price_scale();
        uint256 amount0 = amount * price / 1e18;
        uint256 amount1 = amount;
        
        console2.log("amount0: %s", amount0, IERC20(token0).balanceOf(Protocol.TREASURY));
        console2.log("amount1: %s", amount1, rsup.balanceOf(Protocol.TREASURY));

        _executeTreasury(token0, abi.encodeWithSelector(IERC20.approve.selector, address(pool), type(uint256).max));
        _executeTreasury(token1, abi.encodeWithSelector(IERC20.approve.selector, address(pool), type(uint256).max));

        // Checks
        require(IERC20(token0).allowance(Protocol.TREASURY, address(pool)) > 0, "Not enough token0 allowance");
        require(rsup.allowance(Protocol.TREASURY, address(pool)) > 0, "Not enough rsup allowance");
        require(IERC20(token0).balanceOf(Protocol.TREASURY) >= amount0, "Not enough token0 balance");
        require(rsup.balanceOf(Protocol.TREASURY) >= amount1, "Not enough rsup balance");

        // Add liquidity
        uint256[2] memory amounts;
        amounts[0] = amount0;
        amounts[1] = amount1;
        _executeTreasury(address(pool), abi.encodeWithSelector(ICurvePool.add_liquidity.selector, amounts, 0, Protocol.TREASURY));

        require(pool.balanceOf(Protocol.TREASURY) > 0, "LPs not in treasury");
    }


    function setOperatorPermissions() internal {
        _executeCore(
            address(Protocol.CORE),
            abi.encodeWithSelector(
                ICore.setOperatorPermissions.selector,
                deployer,
                Protocol.VEST_MANAGER,
                IVestManager.setLockPenaltyMerkleRoot.selector,
                true,
                address(0)
            )
        );

        _executeCore(
            address(Protocol.CORE),
            abi.encodeWithSelector(
                ICore.setOperatorPermissions.selector,
                deployer,
                Protocol.TREASURY,
                ITreasury.retrieveToken.selector,
                true,
                address(0)
            )
        );

        _executeCore(
            address(Protocol.CORE),
            abi.encodeWithSelector(
                ICore.setOperatorPermissions.selector,
                deployer,
                Protocol.TREASURY,
                ITreasury.retrieveETH.selector,
                true,
                address(0)
            )
        );

        _executeCore(
            address(Protocol.CORE),
            abi.encodeWithSelector(
                ICore.setOperatorPermissions.selector,
                deployer,
                Protocol.TREASURY,
                ITreasury.retrieveTokenExact.selector,
                true,
                address(0)
            )
        );

        _executeCore(
            address(Protocol.CORE),
            abi.encodeWithSelector(
                ICore.setOperatorPermissions.selector,
                deployer,
                Protocol.TREASURY,
                ITreasury.retrieveETHExact.selector,
                true,
                address(0)
            )
        );

        _executeCore(
            address(Protocol.CORE),
            abi.encodeWithSelector(
                ICore.setOperatorPermissions.selector,
                deployer,
                Protocol.TREASURY,
                ITreasury.safeExecute.selector,
                true,
                address(0)
            )
        );

        _executeCore(
            address(Protocol.CORE),
            abi.encodeWithSelector(
                ICore.setOperatorPermissions.selector,
                deployer,
                Protocol.TREASURY,
                ITreasury.execute.selector,
                true,
                address(0)
            )
        );

         _executeCore(
            address(Protocol.CORE),
            abi.encodeWithSelector(
                ICore.setOperatorPermissions.selector,
                deployer,
                Protocol.TREASURY,
                ITreasury.setTokenApproval.selector,
                true,
                address(0)
            )
        );
    }

    function updateVestSettingsAndClaim() public returns (uint256) {
        // Update vest settings
        _executeTreasury(
            address(vestManager),
            abi.encodeWithSelector(
                IVestManager.setClaimSettings.selector, 
                true,       // enable permissionless claims
                address(0)  // default recipient
            )
        );
        
        // Claim vested tokens
        bytes memory result = addToBatch(
            address(vestManager),
            abi.encodeWithSelector(
                IVestManager.claim.selector, 
                address(Protocol.TREASURY)
            )
        );
        require(rsup.balanceOf(address(Protocol.TREASURY)) > 0, "Not enough vested tokens");
        return uint256(bytes32(result)); // Cast result bytes
    }

    function initVestManager() public {
        _executeCore(
            address(vestManager),
            abi.encodeWithSelector(
                IVestManager.setInitializationParams.selector,
                VMConstants.MAX_REDEEMABLE, // _maxRedeemable
                [
                    VMConstants.TEAM_MERKLE_ROOT, // Team
                    VMConstants.VICTIMS_MERKLE_ROOT, // Victims
                    bytes32(0) // Lock Penalty: We set this one later
                ],
                [   // _nonUserTargets
                    Protocol.PERMA_STAKER_CONVEX,
                    Protocol.PERMA_STAKER_YEARN,
                    VMConstants.FRAX_VEST_TARGET,
                    Protocol.TREASURY
                ],
                [   // _durations
                    VMConstants.DURATION_PERMA_STAKER,         // PERMA_STAKER: Convex
                    VMConstants.DURATION_PERMA_STAKER,         // PERMA_STAKER: Yearn
                    VMConstants.DURATION_LICENSING,            // LICENSING: FRAX
                    VMConstants.DURATION_TREASURY,             // TREASURY
                    VMConstants.DURATION_REDEMPTIONS,          // REDEMPTIONS
                    VMConstants.DURATION_AIRDROP_TEAM,         // AIRDROP_TEAM
                    VMConstants.DURATION_AIRDROP_VICTIMS,      // AIRDROP_VICTIMS
                    VMConstants.DURATION_AIRDROP_LOCK_PENALTY  // AIRDROP_LOCK_PENALTY
                ],
                [ // _allocPercentages
                    VMConstants.ALLOC_PERMA_STAKER_1,       // 33.33% PERMA_STAKER: Convex
                    VMConstants.ALLOC_PERMA_STAKER_2,       // 16.67% PERMA_STAKER: Yearn
                    VMConstants.ALLOC_LICENSING,            // 0.833% LICENSING: FRAX
                    VMConstants.ALLOC_TREASURY,             // 17.50% TREASURY
                    VMConstants.ALLOC_REDEMPTIONS,          // 25.00% REDEMPTIONS
                    VMConstants.ALLOC_AIRDROP_TEAM,         // 3.33% AIRDROP_TEAM
                    VMConstants.ALLOC_AIRDROP_VICTIMS,      // 3.33% AIRDROP_VICTIMS
                    VMConstants.ALLOC_AIRDROP_LOCK_PENALTY  // 0%   AIRDROP_LOCK_PENALTY
                ]
            )
        );
    }

    function withdrawFees() public {
        skip(epochLength);
        addToBatch(
            address(feeDepositController), 
            abi.encodeWithSelector(IFeeDepositController.distribute.selector)
        );
        address[] memory pairs = getPairs();
        for (uint256 i = 0; i < pairs.length; i++) {
            addToBatch(
                pairs[i],
                abi.encodeWithSelector(IResupplyPair.withdrawFees.selector)
            );
        }
        SimpleRewardStreamer debtemissionStreamer = SimpleRewardStreamer(address(Protocol.EMISSIONS_STREAM_PAIR));
        require(IERC20(Protocol.GOV_TOKEN).balanceOf(address(debtemissionStreamer)) > 0, "no emissions on debt emission streamer");
        require(debtemissionStreamer.rewardRate() > 0, "no reward rate for debt emissions");
    }

    function getPairs() public view returns (address[] memory) {
        return IResupplyRegistry(Protocol.REGISTRY).getAllPairAddresses();
    }
}