import "src/Constants.sol" as Constants;
import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { DeploymentConfig } from "script/deploy/dependencies/DeploymentConfig.sol";
import { Protocol, VMConstants } from "script/protocol/ProtocolConstants.sol";
import { ResupplyPairDeployer } from "src/protocol/ResupplyPairDeployer.sol";
import { ResupplyPair } from "src/protocol/ResupplyPair.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { ICurvePool } from "src/interfaces/ICurvePool.sol";
import { console } from "forge-std/console.sol";
import { console2 } from "forge-std/console2.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DeployPair is BaseAction {
    address public constant deployer = Protocol.DEPLOYER;
    address public constant TREASURY = Protocol.TREASURY;
    IERC20 public constant rsup = IERC20(Protocol.GOV_TOKEN);

    uint256 public constant CURVELEND = 0;
    uint256 public constant FRAXLEND = 1;

    uint256 public constant BORROW_LIMIT = 25_000_000e18;

    function run() public isBatch(deployer) {
        deployMode = DeployMode.PRODUCTION;

        //run if implementation should be updated before adding pair
        // updatePairImplementation();
        
        // address pair = deployLendingPair(FRAXLEND,address(Constants.Mainnet.FRAXLEND_WBTC_FRXUSD), address(0), uint256(0));
        address pair = deployLendingPair(CURVELEND,address(Constants.Mainnet.CURVELEND_SDOLA2_CRVUSD), address(Constants.Mainnet.CONVEX_BOOSTER), uint256(Constants.Mainnet.CURVELEND_SDOLA2_CRVUSD_ID));
        console.log('pair deployed: ', pair);
        console.log('collateral: ', IResupplyPair(pair).collateral());
        console.log('underlying: ', IResupplyPair(pair).underlying());


        if (deployMode == DeployMode.PRODUCTION) executeBatch(true, 41);
    }

    function updatePairImplementation() public{
        _executeCore(Protocol.PAIR_DEPLOYER, abi.encodeWithSelector(ResupplyPairDeployer.setCreationCode.selector, type(ResupplyPair).creationCode));
    }

    function deployLendingPair(uint256 _protocolId, address _collateral, address _staking, uint256 _stakingId) public returns(address){
        bytes memory result;
        result = _executeCore(
            address(Protocol.PAIR_DEPLOYER),
            abi.encodeWithSelector(ResupplyPairDeployer.deploy.selector,
                _protocolId,
                abi.encode(
                    _collateral,
                    address(Protocol.BASIC_VAULT_ORACLE),
                    address(Protocol.INTEREST_RATE_CALCULATOR),
                    DeploymentConfig.DEFAULT_MAX_LTV,
                    BORROW_LIMIT,//DeploymentConfig.DEFAULT_BORROW_LIMIT,
                    DeploymentConfig.DEFAULT_LIQ_FEE,
                    DeploymentConfig.DEFAULT_MINT_FEE,
                    DeploymentConfig.DEFAULT_PROTOCOL_REDEMPTION_FEE
                ),
                _staking,
                _stakingId
            )
        );
        result = abi.decode(result, (bytes)); // our result was double encoded, so we decode it once
        address pair = abi.decode(result, (address));
        _executeCore(
            address(Protocol.REGISTRY),
            abi.encodeWithSelector(IResupplyRegistry.addPair.selector, pair)
        );
        return pair;
    }
}