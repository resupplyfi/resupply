pragma solidity 0.8.28;

import "src/Constants.sol" as Constants;
import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { DeploymentConfig } from "src/Constants.sol";
import { Protocol, VMConstants } from "src/Constants.sol";
import { ResupplyPairDeployer } from "src/protocol/ResupplyPairDeployer.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { ICurvePool } from "src/interfaces/curve/ICurvePool.sol";
import { console } from "forge-std/console.sol";
import { console2 } from "forge-std/console2.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ResupplyPairConvex } from "src/protocol/pair/ResupplyPairConvex.sol";

contract DeployPair is BaseAction {
    address public constant deployer = Protocol.DEPLOYER;
    address public constant TREASURY = Protocol.TREASURY;
    IERC20 public constant rsup = IERC20(Protocol.GOV_TOKEN);

    uint256 public constant CURVELEND = 0;
    uint256 public constant FRAXLEND = 1;

    uint256 public constant BORROW_LIMIT = 25_000_000e18;

    bool private UPDATE_IMPLEMENTATION = false;
    bool private ADD_TO_REGISTRY = true;

    function run() public isBatch(deployer) {
        deployMode = DeployMode.FORK;

        //run if implementation should be updated before adding pair
        if(UPDATE_IMPLEMENTATION){
            updatePairImplementation();
        }
        
        // address pair = deployLendingPair(FRAXLEND,address(Constants.Mainnet.FRAXLEND_WBTC_FRXUSD), address(0), uint256(0));
        address pair = deployLendingPair(CURVELEND,address(Constants.Mainnet.CURVELEND_SDOLA2_CRVUSD), address(Constants.Mainnet.CONVEX_BOOSTER), uint256(Constants.Mainnet.CURVELEND_SDOLA2_CRVUSD_ID));
        printPairVersion(pair);
        
        if(ADD_TO_REGISTRY){
            addToRegistry(pair);
        }

        if (deployMode == DeployMode.PRODUCTION) executeBatch(true);
    }

    function printPairVersion(address _pair) public{
        (uint256 major, uint256 minor, uint256 patch) = IResupplyPair(_pair).version();
        console.log("pair version: ", string.concat(
            vm.toString(major),
            ".",
            vm.toString(minor),
            ".",
            vm.toString(patch)
        ));
    }

    function updatePairImplementation() public{
        console.log("\n*** updating implementation...");
        _executeCore(Protocol.PAIR_DEPLOYER_V2, abi.encodeWithSelector(ResupplyPairDeployer.setCreationCode.selector, type(ResupplyPairConvex).creationCode));
    }

    function deployLendingPair(uint256 _protocolId, address _collateral, address _staking, uint256 _stakingId) public returns(address){
        console.log("\n*** deploying pair...");
        
        bytes memory configdata = abi.encode(
                    _collateral,
                    address(Protocol.BASIC_VAULT_ORACLE),
                    address(Protocol.INTEREST_RATE_CALCULATOR),
                    DeploymentConfig.DEFAULT_MAX_LTV,
                    BORROW_LIMIT,//DeploymentConfig.DEFAULT_BORROW_LIMIT,
                    DeploymentConfig.DEFAULT_LIQ_FEE,
                    DeploymentConfig.DEFAULT_MINT_FEE,
                    DeploymentConfig.DEFAULT_PROTOCOL_REDEMPTION_FEE
                );
        bytes memory immutables = abi.encode(address(Protocol.REGISTRY));

        bytes memory result;
        result = _executeCore(
            address(Protocol.PAIR_DEPLOYER_V2),
            abi.encodeWithSignature("deploy(uint256,bytes,address,uint256)",
                _protocolId,
                configdata,
                _staking,
                _stakingId
            )
        );
        result = abi.decode(result, (bytes)); // our result was double encoded, so we decode it once
        address pair = abi.decode(result, (address));

        string memory name = IResupplyPair(pair).name();
        bytes memory customData = abi.encode(name, address(Protocol.GOV_TOKEN), _staking, _stakingId);
        bytes memory constructorData = abi.encode(Protocol.CORE, configdata, immutables, customData);

        console.log('pair deployed: ', pair);
        console.log('collateral: ', IResupplyPair(pair).collateral());
        console.log('underlying: ', IResupplyPair(pair).underlying());
        console.log('constructor args:');
        console.logBytes(constructorData);

        return pair;
    }

    function addToRegistry(address _pair) public{
        console.log("\n*** adding to registry...");
        //add to registry
        _executeCore(
            address(Protocol.REGISTRY),
            abi.encodeWithSelector(IResupplyRegistry.addPair.selector, _pair)
        );

        //call withdraw fees to hook up incentives
        addToBatch(
            _pair, 
            abi.encodeWithSelector(IResupplyPair.withdrawFees.selector)
        );
    }
}