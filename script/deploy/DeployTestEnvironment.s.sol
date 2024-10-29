// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import { BaseScript } from "frax-std/BaseScript.sol";
import { console } from "frax-std/FraxTest.sol";
import "src/Constants.sol" as Constants;
import { DeployScriptReturn } from "./DeployScriptReturn.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ResupplyPairRegistry } from "src/protocol/ResupplyPairRegistry.sol";
import { ResupplyPairDeployer } from "src/protocol/ResupplyPairDeployer.sol";
import { StableCoin } from "src/protocol/StableCoin.sol";
import { InterestRateCalculator } from "src/protocol/InterestRateCalculator.sol";
import { BasicVaultOracle } from "src/protocol/BasicVaultOracle.sol";
import { ResupplyPair } from "src/protocol/ResupplyPair.sol";
import { InsurancePool } from "src/protocol/InsurancePool.sol";
import { SimpleRewardStreamer } from "src/protocol/SimpleRewardStreamer.sol";
import { FeeDeposit } from "src/protocol/FeeDeposit.sol";
import { FeeDepositController } from "src/protocol/FeeDepositController.sol";
import { RedemptionHandler } from "src/protocol/RedemptionHandler.sol";
import { LiquidationHandler } from "src/protocol/LiquidationHandler.sol";
import { RewardHandler } from "src/protocol/RewardHandler.sol";



contract DeployTestEnvironment is BaseScript {
    uint256 internal constant DEFAULT_MAX_LTV = 95_000; // 75% with 1e5 precision
    uint256 internal constant DEFAULT_LIQ_FEE = 500; // 5% with 1e5 precision
    uint256 internal constant DEFAULT_BORROW_LIMIT = 5_000_000 * 1e18;
    uint256 internal constant DEFAULT_MINT_FEE = 0; //1e5 prevision
    uint256 internal constant DEFAULT_PROTOCOL_REDEMPTION_FEE = 1e18 / 2; //half

    function run() external broadcaster returns (DeployScriptReturn[] memory _return) {
        _return = deployEnvironment();
    }

    function setReturnData(address _address, bytes memory _constructor, string memory _name) private returns(DeployScriptReturn memory _return){
        _return.address_ = _address;
        _return.constructorParams = _constructor;
        _return.contractName = _name;
    }

    function deployOthers(address _core, address _pairRegistry, address _stable, address _gov) private returns(DeployScriptReturn[] memory _return){
        _return = new DeployScriptReturn[](9);

        InsurancePool _insurancepool = new InsurancePool(
        address(_core), //core
        address(_stable),
        address(_pairRegistry));

        _return[0].address_ = address(_insurancepool);
        _return[0].constructorParams = "";
        _return[0].contractName = "Insurance Pool";

        SimpleRewardStreamer _ipstablestream = new SimpleRewardStreamer(
            address(_stable),
            address(_pairRegistry),
            address(_core), //core
            address(_insurancepool));
        _return[1].address_ = address(_ipstablestream);
        _return[1].constructorParams = "";
        _return[1].contractName = "Insurance Pool Revenue Stream";

        SimpleRewardStreamer _ipemissionstream = new SimpleRewardStreamer(
            address(_gov),
            address(_pairRegistry),
            address(_core), //core
            address(_insurancepool));
        _return[2] = setReturnData(address(_ipemissionstream),"","Insurance Pool Emissions Stream");

        //todo add rewards to pool

        SimpleRewardStreamer _pairemissionstream = new SimpleRewardStreamer(
            address(_gov),
            address(_pairRegistry),
            address(_core), //core
            address(0));
        _return[3] = setReturnData(address(_pairemissionstream),"","Pair Emissions Stream");

        FeeDeposit _feedeposit = new FeeDeposit(
             address(_core), //core
             address(_pairRegistry),
             address(_stable)
             );
        _return[4] = setReturnData(address(_feedeposit),"","Fee Deposit");
        FeeDepositController _feedepositController = new FeeDepositController(
            address(_pairRegistry),
            address(deployer), //treasury
            address(_feedeposit),
            address(_stable),
            1500,
            1000
            );
        _return[5] = setReturnData(address(_feedepositController),"","Fee Deposit Controller");

        RedemptionHandler _redemptionHandler = new RedemptionHandler(
            address(_core),//core
            address(_pairRegistry),
            address(_stable)
            );
        _return[6] = setReturnData(address(_redemptionHandler),"","Redemption Handler");

        LiquidationHandler _liqHandler = new LiquidationHandler(
            address(_core),//core
            address(_pairRegistry),
            address(_insurancepool)
            );
        _return[7] = setReturnData(address(_liqHandler),"","Liquidation Handler");

        RewardHandler _rewardHandler = new RewardHandler(
            address(_core),//core
            address(_pairRegistry),
            address(_stable),
            address(_pairemissionstream), //todo gov staking
            address(_insurancepool),
            address(_pairemissionstream),
            address(_ipemissionstream),
            address(_ipstablestream)
            );
        _return[8] = setReturnData(address(_rewardHandler),"","Reward Handler");
    }

    function deployEnvironment() private returns (DeployScriptReturn[] memory _return) {
        _return = new DeployScriptReturn[](17);

        // address deployer = msg.sender;
        address deployer = vm.rememberKey(vm.envUint("PK"));
        console.log(">>> deploying from:", deployer);

        StableCoin _stable = new StableCoin(deployer);
        StableCoin _gov = new StableCoin(deployer);

        console.log("owner/core: ", _stable.owner());
        _stable.setOperator(deployer,true);
        _gov.setOperator(deployer,true);
        _stable.mint(deployer,100_000 * 1e18);
        _gov.mint(deployer,100_000 * 1e18);
        

        _return[0].address_ = address(_stable);
        _return[0].constructorParams = "";
        _return[0].contractName = "StableCoin";

        _return[1].address_ = address(_stable);
        _return[1].constructorParams = "";
        _return[1].contractName = "GovToken";

        ResupplyPairRegistry _pairRegistry = new ResupplyPairRegistry(
            address(_stable),
            address(deployer)
        );
        _return[2].address_ = address(_pairRegistry);
        _return[2].constructorParams = "";
        _return[2].contractName = "ResupplyPairRegistry";

        //give registry mint rights
        _stable.setOperator(address(_pairRegistry),true);

        ResupplyPairDeployer _pairDeployer = new ResupplyPairDeployer(
            address(_pairRegistry),
            address(_gov),
            address(deployer),
            address(deployer)
        );
        _return[3].address_ = address(_pairDeployer);
        _return[3].constructorParams = "";
        _return[3].contractName = "ResupplyPairDeployer";
        _pairDeployer.setCreationCode(type(ResupplyPair).creationCode);

        InterestRateCalculator _rateCalc = new InterestRateCalculator(
            "Base",
            634_195_840,//(2 * 1e16) / 365 / 86400, //2% todo check
            2
        );
        _return[4].address_ = address(_rateCalc);
        _return[4].constructorParams = "";
        _return[4].contractName = "InterestRateCalculator";

        BasicVaultOracle _oracle = new BasicVaultOracle(
            "Basic Vault Oracle"
        );
        _return[5].address_ = address(_oracle);
        _return[5].constructorParams = "";
        _return[5].contractName = "BasicVaultOracle";

        address _fraxlendpairAddress = _pairDeployer.deploy(
            abi.encode(
                address(Constants.Mainnet.FRAX_ERC20),
                address(Constants.Mainnet.FRAXLEND_SFRXETH_FRAX),
                address(_oracle),
                address(_rateCalc),
                DEFAULT_MAX_LTV,
                DEFAULT_BORROW_LIMIT,
                DEFAULT_LIQ_FEE,
                DEFAULT_MINT_FEE,
                DEFAULT_PROTOCOL_REDEMPTION_FEE
            ),
            address(0), //staking
            0, //staking id
            0 //resupply unique id
        );

        _return[6].address_ = address(_fraxlendpairAddress);
        _return[6].constructorParams = "";
        _return[6].contractName = "Fraxlend Pair SFRXETH FRAX";

        address _curvelendpairAddress = _pairDeployer.deploy(
            abi.encode(
                address(Constants.Mainnet.CURVE_USD_ERC20),
                address(Constants.Mainnet.CURVELEND_SFRAX_CRVUSD),
                address(_oracle),
                address(_rateCalc),
                DEFAULT_MAX_LTV,
                DEFAULT_BORROW_LIMIT,
                DEFAULT_LIQ_FEE,
                DEFAULT_MINT_FEE,
                DEFAULT_PROTOCOL_REDEMPTION_FEE
            ),
            address(Constants.Mainnet.CONVEX_BOOSTER), //staking
            uint256(Constants.Mainnet.CURVELEND_SFRAX_CRVUSD_ID), //staking id
            1 //resupply unique id
        );

        _return[7].address_ = address(_curvelendpairAddress);
        _return[7].constructorParams = "";
        _return[7].contractName = "Curvelend Pair SFRAX CRVUSD";

        _pairRegistry.addPair(_fraxlendpairAddress);
        _pairRegistry.addPair(_curvelendpairAddress);

        
        DeployScriptReturn[] memory _subreturn = deployOthers(deployer, address(_pairRegistry), address(_stable), address(_gov));
        for(uint256 i=0; i < _subreturn.length; i++){
            _return[i+8] = _subreturn[i];
        }

        console.log("======================================");
        console.log("    Base Contracts     ");
        console.log("======================================");
        console.log("Registry: ", address(_pairRegistry));
        console.log("Deployer: ", address(_pairDeployer));
        console.log("govToken: ", address(_gov));
        console.log("stableToken: ", address(_stable));
        console.log("rate calculator: ", address(_rateCalc));
        console.log("oracle: ", address(_oracle));
        console.log("fraxlend pair: ", address(_fraxlendpairAddress));
        console.log("curvelend pair: ", address(_curvelendpairAddress));
        console.log("======================================");
        console.log("balance of reUSD: ", _stable.balanceOf(deployer));
        console.log("balance of RSPL: ", _gov.balanceOf(deployer));
        // console.log("balance of frax: ", fraxToken.balanceOf(deployer));
        // console.log("balance of crvusd: ", crvUsdToken.balanceOf(deployer));
    }
}
