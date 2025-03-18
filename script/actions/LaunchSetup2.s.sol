import { IVestManager } from "src/interfaces/IVestManager.sol";
import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { Protocol, VMConstants } from "script/protocol/ProtocolConstants.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { ICurveExchange } from "src/interfaces/ICurveExchange.sol";
import { console2 } from "forge-std/console2.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IFeeDepositController } from "src/interfaces/IFeeDepositController.sol";

contract LaunchSetup2 is BaseAction {
    address public constant deployer = Protocol.DEPLOYER;
    address public constant TREASURY = Protocol.TREASURY;
    IVestManager public constant vestManager = IVestManager(Protocol.VEST_MANAGER);
    ICurveExchange public constant pool = ICurveExchange(Protocol.WETH_RSUP_POOL);
    uint256 public constant DEFAULT_BORROW_LIMIT = 25_000_000e18;
    IFeeDepositController public constant feeDepositController = IFeeDepositController(Protocol.FEE_DEPOSIT_CONTROLLER);

    function run() public isBatch(deployer) {
        deployMode = DeployMode.FORK;
        setBorrowLimits();
        initVestManager();
        uint256 amount = updateVestSettingsAndClaim();
        // createLP(amount);
        // withdrawFees();
    }
        
    function setBorrowLimits() public {
        address[] memory pairs = getPairs();
        for (uint256 i = 0; i < pairs.length; i++) {
            uint256 limit = DEFAULT_BORROW_LIMIT;
            if (pairs[i] == address(Protocol.PAIR_CURVELEND_SFRXUSD_CRVUSD)) limit = 50_000_000e18;
            else if (pairs[i] == address(Protocol.PAIR_FRAXLEND_SFRXETH_FRXUSD)) limit = 50_000_000e18;
            else if (
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
        uint256 price = pool.price_scale();
        uint256 amount0 = amount * price / 1e18;
        uint256 amount1 = amount;
        
        console2.log("amount0: %s", amount0);
        console2.log("amount1: %s", amount1);
        _executeCore(token0, abi.encodeWithSelector(IERC20.approve.selector, address(pool), type(uint256).max));
        _executeCore(token1, abi.encodeWithSelector(IERC20.approve.selector, address(pool), type(uint256).max));
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
        return uint256(bytes32(result));//uint256(bytes32(abi.decode(result, (bytes))));
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
        feeDepositController.distribute();
        address[] memory pairs = getPairs();
        for (uint256 i = 0; i < pairs.length; i++) {
            // Doesn't require Core permission
            addToBatch(
                pairs[i],
                abi.encodeWithSelector(IResupplyPair.withdrawFees.selector)
            );
        }
    }

    function getPairs() public view returns (address[] memory) {
        return IResupplyRegistry(Protocol.REGISTRY).getAllPairAddresses();
    }
}