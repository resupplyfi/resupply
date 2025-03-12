import "src/Constants.sol" as Constants;
import { DeploymentConfig } from "script/deploy/dependencies/DeploymentConfig.sol";
import { console } from "forge-std/console.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { BaseDeploy } from "script/deploy/dependencies/BaseDeploy.s.sol";
import { DeployResupply } from "script/deploy/DeployResupply.s.sol";
import { ICore } from "src/interfaces/ICore.sol";
import { ICurveExchange } from "src/interfaces/ICurveExchange.sol";
import { Swapper } from "src/protocol/Swapper.sol";
import { ResupplyPairDeployer } from "src/protocol/ResupplyPairDeployer.sol";
import { BasicVaultOracle } from "src/protocol/BasicVaultOracle.sol";
import { InterestRateCalculator } from "src/protocol/InterestRateCalculator.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";

contract TestEnvironmentSetup is DeployResupply {

    function run() public override isBatch(deployer) {
        deployMode = DeployMode.TENDERLY;
        crvusdPool = 0x3f3FA55cb5a9908efB10aC018C9f631789d87198;
        fraxPool = 0xDd6B8c4a3b0dCE4B5b554d9b0CBFD6dfAE83e86F;
        core = 0xc07e000044F95655c11fda4cD37F70A94d7e0a7d;
        oracle = BasicVaultOracle(0xcb7E25fbbd8aFE4ce73D7Dac647dbC3D847F3c82);
        rateCalculator = InterestRateCalculator(0x3b7AbCB8E1d7E2F1ba89BF5Eec037F07F2ed2CCF);
        pairDeployer = ResupplyPairDeployer(0x5555555524De7C56C1B20128dbEAace47d2C0417);
        registry = IResupplyRegistry(0x10101010E0C3171D894B71B3400668aF311e7D94);
        issueTokens();
        // deployExtraPair();
        provideLiquidity();
        handoffGovernance();
    }

    function deployExtraPair() public {
        bytes memory result = _executeCore(
            address(pairDeployer),
            abi.encodeWithSelector(
                ResupplyPairDeployer.deploy.selector,
                0,
                abi.encode(
                    Constants.Mainnet.CURVELEND_SDOLA_CRVUSD,
                    address(oracle),
                    address(rateCalculator),
                    DeploymentConfig.DEFAULT_MAX_LTV, //max ltv 75%
                    defaultBorrowLimit,
                    DeploymentConfig.DEFAULT_LIQ_FEE,
                    DeploymentConfig.DEFAULT_MINT_FEE,
                    DeploymentConfig.DEFAULT_PROTOCOL_REDEMPTION_FEE
                ),
                Constants.Mainnet.CONVEX_BOOSTER,
                Constants.Mainnet.CURVELEND_SDOLA_CRVUSD_ID
            )
        );
        result = abi.decode(result, (bytes));
        address pair = abi.decode(result, (address));
        _executeCore(
            address(registry),
            abi.encodeWithSelector(IResupplyRegistry.addPair.selector, pair)
        );
        console.log("Pair deployed at", pair);
        writeAddressToJson("CURVELEND_SDOLA_CRVUSD", pair);
    }

    function handoffGovernance() public {
        address _voter = 0x111111110d3e18e73CC2227A40B565043266DaC1;
        _executeCore(address(core), abi.encodeWithSelector(ICore.setVoter.selector, _voter));
    }

    function issueTokens() public {
        address _stablecoin = 0x57aB1E0003F623289CD798B1824Be09a793e4Bec;
        setTokenBalance(_stablecoin, deployer, 100_000_000e18);
        setTokenBalance(DeploymentConfig.SCRVUSD, deployer, 100_000_000e18);
        setTokenBalance(DeploymentConfig.SFRXUSD, deployer, 100_000_000e18);
        console.log("stablecoin balance of deployer", IERC20(_stablecoin).balanceOf(deployer));
    }

    function provideLiquidity() public isBatch(deployer) {
        address _stablecoin = 0x57aB1E0003F623289CD798B1824Be09a793e4Bec;
        // Approve tokens for both pools
        addToBatch(
            _stablecoin,
            abi.encodeWithSelector(IERC20.approve.selector, crvusdPool, type(uint256).max)
        );
        addToBatch(
            address(DeploymentConfig.SCRVUSD),
            abi.encodeWithSelector(IERC20.approve.selector, crvusdPool, type(uint256).max)
        );
        addToBatch(
            address(DeploymentConfig.SFRXUSD),
            abi.encodeWithSelector(IERC20.approve.selector, fraxPool, type(uint256).max)
        );
        addToBatch(
            address(_stablecoin),
            abi.encodeWithSelector(IERC20.approve.selector, fraxPool, type(uint256).max)
        );
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1_000_000e18;
        amounts[1] = 1_000_000e18;

        // Add liquidity to reUSD/scrvUSD pool
        addToBatch(
            crvusdPool,
            abi.encodeWithSelector(ICurveExchange.add_liquidity.selector, amounts, 0, deployer)
        );
        console.log("Added liquidity to reUSD/scrvUSD pool");

        // Add liquidity to reUSD/sfrxUSD pool
        addToBatch(
            fraxPool,
            abi.encodeWithSelector(ICurveExchange.add_liquidity.selector, amounts, 0, deployer)
        );
        console.log("Added liquidity to reUSD/sfrxUSD pool");
    }
}