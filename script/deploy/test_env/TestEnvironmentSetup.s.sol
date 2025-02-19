import "src/Constants.sol" as Constants;
import { console } from "forge-std/console.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { BaseDeploy } from "script/deploy/dependencies/BaseDeploy.s.sol";
import { DeployResupply } from "script/deploy/DeployResupply.s.sol";
import { ICore } from "src/interfaces/ICore.sol";
import { ICurveExchange } from "src/interfaces/ICurveExchange.sol";
import { Swapper } from "src/protocol/Swapper.sol";

contract TestEnvironmentSetup is DeployResupply {
    address public scrvusd = Constants.Mainnet.CURVE_SCRVUSD;
    address public sfrxusd = Constants.Mainnet.SFRAX_ERC20;
    address public crvusdPool = 0x8005516831b4DC21aCdc34d5a413F189FC850948;
    address public fraxPool = 0xd6891003c66371606d85a33f694768b0e7738291;
    Swapper public defaultSwapper;


    function run() public override {
        deployMode = DeployMode.TENDERLY;
        super.deployAll();
        issueTokens();
        deployCurvePools();
        deploySwapper();
        handoffGovernance();
        provideLiquidity();
    }

    function handoffGovernance() public {
        _executeCore(address(core), abi.encodeWithSelector(ICore.setVoter.selector, address(voter)));
    }

    function issueTokens() public {
        address _stablecoin = 0x57aB1E0003F623289CD798B1824Be09a793e4Bec;
        setTokenBalance(_stablecoin, dev, 100_000_000e18);
        console.log("stablecoin balance of dev", IERC20(_stablecoin).balanceOf(dev));
        setTokenBalance(scrvusd, dev, 100_000_000e18);
        setTokenBalance(sfrxusd, dev, 100_000_000e18);
    }

    function deployCurvePools() public{
        address[] memory coins = new address[](2);
        coins[0] = address(stablecoin);
        coins[1] = scrvusd;
        uint8[] memory assetTypes = new uint8[](2);
        assetTypes[1] = 3; //second coin is erc4626
        bytes4[] memory methods = new bytes4[](2);
        address[] memory oracles = new address[](2);
        bytes memory result;
        result = addToBatch(
            address(Constants.Mainnet.CURVE_STABLE_FACTORY),
            abi.encodeWithSelector(ICurveExchange.deploy_plain_pool.selector,
                "reUSD/scrvUSD",    // name
                "reusdscrv",        // symbol
                coins,              // coins
                200,                // A
                4000000,            // fee
                50000000000,        // off peg multi
                866,                // ma exp time
                0,                  // implementation index
                assetTypes,         // asset types - normal + erc4626
                methods,            // method ids
                oracles             // oracles
            )
        );
        crvusdPool = abi.decode(result, (address));
        console.log("reUSD/scrvUSD Pool deployed at", crvusdPool);
        //TODO, update to sfrxusd from sfrax
        coins[1] = sfrxusd;
        result = addToBatch(
            address(Constants.Mainnet.CURVE_STABLE_FACTORY),
            abi.encodeWithSelector(ICurveExchange.deploy_plain_pool.selector,
                "reUSD/sfrxUSD",    //name
                "reusdsfrx",        //symbol
                coins,              //coins
                200,                //A
                4000000,            //fee
                50000000000,        //off peg multi
                866,                //ma exp time
                0,                  //implementation index
                assetTypes,         //asset types - normal + erc4626
                methods,            //method ids
                oracles             //oracles
            )
        );
        fraxPool = abi.decode(result, (address));
        console.log("reUSD/sfrxUSD Pool deployed at", fraxPool);
    }

    function provideLiquidity() public isBatch(dev) {
        // Add liquidity to reUSD/scrvUSD pool
        // TODO: Not yet able to figure out how to get tenderly API to fund dev account with `stablecoin`
        address _stablecoin = 0x57aB1E0003F623289CD798B1824Be09a793e4Bec;
        // Approve tokens for both pools
        addToBatch(
            _stablecoin,
            abi.encodeWithSelector(IERC20.approve.selector, crvusdPool, type(uint256).max)
        );
        addToBatch(
            address(scrvusd),
            abi.encodeWithSelector(IERC20.approve.selector, crvusdPool, type(uint256).max)
        );
        addToBatch(
            address(sfrxusd),
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
            abi.encodeWithSelector(ICurveExchange.add_liquidity.selector, amounts, 0, dev)
        );
        console.log("Added liquidity to reUSD/scrvUSD pool");

        // Add liquidity to reUSD/sfrxUSD pool
        addToBatch(
            fraxPool,
            abi.encodeWithSelector(ICurveExchange.add_liquidity.selector, amounts, 0, dev)
        );
        console.log("Added liquidity to reUSD/sfrxUSD pool");
    }

    function deploySwapper() public {
        //deploy swapper
        bytes32 salt = buildGuardedSalt(dev, true, false, uint88(uint256(keccak256(bytes("Swapper")))));
        bytes memory bytecode = abi.encodePacked(vm.getCode("Swapper.sol:Swapper"), abi.encode(address(core)));
        address predictedAddress = computeCreate3AddressFromSaltPreimage(salt, dev, true, false);
        if (addressHasCode(predictedAddress)) revert("Swapper already deployed");
        addToBatch(
            address(createXFactory),
            encodeCREATE3Deployment(
                salt, 
                bytecode
            )
        );
        defaultSwapper = Swapper(predictedAddress);

        Swapper.SwapInfo memory swapinfo;

        //reusd to scrvusd
        swapinfo.swappool = crvusdPool;
        swapinfo.tokenInIndex = 0;
        swapinfo.tokenOutIndex = 1;
        swapinfo.swaptype = 1;
        _executeCore(address(defaultSwapper), abi.encodeWithSelector(Swapper.addPairing.selector, address(stablecoin), Constants.Mainnet.CURVE_SCRVUSD, swapinfo));

        //scrvusd to reusd
        swapinfo.swappool = crvusdPool;
        swapinfo.tokenInIndex = 1;
        swapinfo.tokenOutIndex = 0;
        swapinfo.swaptype = 1;
        _executeCore(address(defaultSwapper), abi.encodeWithSelector(Swapper.addPairing.selector, Constants.Mainnet.CURVE_SCRVUSD, address(stablecoin), swapinfo));

        //scrvusd withdraw to crvusd
        swapinfo.swappool = Constants.Mainnet.CURVE_SCRVUSD;
        swapinfo.tokenInIndex = 0;
        swapinfo.tokenOutIndex = 0;
        swapinfo.swaptype = 3;
        _executeCore(address(defaultSwapper), abi.encodeWithSelector(Swapper.addPairing.selector, Constants.Mainnet.CURVE_SCRVUSD, Constants.Mainnet.CURVE_USD_ERC20, swapinfo));

        //crvusd deposit to scrvusd
        swapinfo.swappool = Constants.Mainnet.CURVE_SCRVUSD;
        swapinfo.tokenInIndex = 0;
        swapinfo.tokenOutIndex = 0;
        swapinfo.swaptype = 2;
        _executeCore(address(defaultSwapper), abi.encodeWithSelector(Swapper.addPairing.selector, Constants.Mainnet.CURVE_USD_ERC20, Constants.Mainnet.CURVE_SCRVUSD, swapinfo));

        //reusd to sfrxusd
        swapinfo.swappool = fraxPool;
        swapinfo.tokenInIndex = 0;
        swapinfo.tokenOutIndex = 1;
        swapinfo.swaptype = 1;
        _executeCore(address(defaultSwapper), abi.encodeWithSelector(Swapper.addPairing.selector, address(stablecoin), Constants.Mainnet.SFRAX_ERC20, swapinfo));

        //sfrxusd to reusd
        swapinfo.swappool = fraxPool;
        swapinfo.tokenInIndex = 1;
        swapinfo.tokenOutIndex = 0;
        swapinfo.swaptype = 1;
        _executeCore(address(defaultSwapper), abi.encodeWithSelector(Swapper.addPairing.selector, Constants.Mainnet.SFRAX_ERC20, address(stablecoin), swapinfo));

        //sfrxusd withdraw to frxusd
        swapinfo.swappool = Constants.Mainnet.SFRAX_ERC20;
        swapinfo.tokenInIndex = 0;
        swapinfo.tokenOutIndex = 0;
        swapinfo.swaptype = 3;
        _executeCore(address(defaultSwapper), abi.encodeWithSelector(Swapper.addPairing.selector, Constants.Mainnet.SFRAX_ERC20, Constants.Mainnet.FRAX_ERC20, swapinfo));

        //frxusd deposit to sfrxusd
        swapinfo.swappool = Constants.Mainnet.SFRAX_ERC20;
        swapinfo.tokenInIndex = 0;
        swapinfo.tokenOutIndex = 0;
        swapinfo.swaptype = 2;
        _executeCore(address(defaultSwapper), abi.encodeWithSelector(Swapper.addPairing.selector, Constants.Mainnet.FRAX_ERC20, Constants.Mainnet.SFRAX_ERC20, swapinfo));


        //set swapper to registry
        address[] memory swappers = new address[](1);
        swappers[0] = address(defaultSwapper);
        _executeCore(address(registry), abi.encodeWithSelector(registry.setDefaultSwappers.selector, swappers));
        console.log("Swapper deployed at", address(defaultSwapper));
        console.log("Swapper configured");
    }
}