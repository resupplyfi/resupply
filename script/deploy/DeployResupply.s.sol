import "src/Constants.sol" as Constants;
import { console } from "forge-std/console.sol";
import { DeployResupplyDao } from "./dependencies/DeployResupplyDao.s.sol";
import { DeployResupplyProtocol } from "./dependencies/DeployResupplyProtocol.s.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IGovStaker } from "src/interfaces/IGovStaker.sol";
import { ResupplyPair } from "src/protocol/ResupplyPair.sol";
import { ResupplyPairDeployer } from "src/protocol/ResupplyPairDeployer.sol";
import { ResupplyRegistry } from "src/protocol/ResupplyRegistry.sol";
import { SimpleReceiver } from "src/dao/emissions/receivers/SimpleReceiver.sol";
import { ICore } from "src/interfaces/ICore.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { Stablecoin } from "src/protocol/Stablecoin.sol";
import { EmissionsController } from "src/dao/emissions/EmissionsController.sol";
import { GovToken } from "src/dao/GovToken.sol";

contract DeployResupply is DeployResupplyDao, DeployResupplyProtocol {

    function run() public virtual {
        deployMode = DeployMode.TENDERLY;
        deployAll();
    }

    function deployAll() isBatch(dev) public {
        setEthBalance(dev, 10e18);
        deployDaoContracts();
        deployProtocolContracts();
        configurationStep1();
        deployRewardsContracts();
        configureProtocolContracts();
        (permaStaker1, permaStaker2) = deployPermaStakers();
        deployDefaultLendingPairs();
        setupEmissionsReceivers();
        grantOperatorPermissions();
    }

    // Deploy incentives reUSD/RSUP incentives receivers and register all receivers with the emissions controller
    function setupEmissionsReceivers() public {
        address[] memory approvedClaimers = new address[](1);
        approvedClaimers[0] = address(dev);
        // Deploy the reUSD Incentives Receiver
        bytes memory result = _executeCore(
            address(receiverFactory), 
            abi.encodeWithSelector(receiverFactory.deployNewReceiver.selector, "reUSD Incentives Receiver", approvedClaimers)
        );
        result = abi.decode(result, (bytes)); // our result was double encoded, so we decode it once
        address reusdIncentivesReceiver = abi.decode(result, (address)); // decode the bytes result to an address
        console.log("reUSD Incentives Receiver deployed at", address(reusdIncentivesReceiver));
        // Deploy the RSUP Incentives Receiver
        result = _executeCore(
            address(receiverFactory), 
            abi.encodeWithSelector(receiverFactory.deployNewReceiver.selector, "RSUP Incentives Receiver", approvedClaimers)
        );
        result = abi.decode(result, (bytes)); // our result was double encoded, so we decode it once
        address rsupIncentivesReceiver = abi.decode(result, (address)); // decode the bytes result to an address
        console.log("RSUP Incentives Receiver deployed at", address(rsupIncentivesReceiver));

        // Register the receivers with the emissions controller
        _executeCore(address(emissionsController), abi.encodeWithSelector(EmissionsController.registerReceiver.selector, address(debtReceiver)));
        _executeCore(address(emissionsController), abi.encodeWithSelector(EmissionsController.registerReceiver.selector, address(insuranceEmissionsReceiver)));
        _executeCore(address(emissionsController), abi.encodeWithSelector(EmissionsController.registerReceiver.selector, address(reusdIncentivesReceiver)));
        _executeCore(address(emissionsController), abi.encodeWithSelector(EmissionsController.registerReceiver.selector, address(rsupIncentivesReceiver)));
        
        // Set the weights for the receivers
        uint256[] memory receiverIds = new uint256[](4);
        receiverIds[0] = 0;
        receiverIds[1] = 1;
        receiverIds[2] = 2;
        receiverIds[3] = 3;
        uint256[] memory weights = new uint256[](4);
        weights[0] = DEBT_RECEIVER_WEIGHT;
        weights[1] = INSURANCE_EMISSIONS_RECEIVER_WEIGHT;
        weights[2] = REUSD_INCENTENIVES_RECEIVER_WEIGHT;
        weights[3] = RSUP_INCENTENIVES_RECEIVER_WEIGHT;
        _executeCore(address(emissionsController), abi.encodeWithSelector(EmissionsController.setReceiverWeights.selector, receiverIds, weights));
    }

    function deployDefaultLendingPairs() public {
        _executeCore(
            address(pairDeployer), 
            abi.encodeWithSelector(
                ResupplyPairDeployer.addSupportedProtocol.selector, 
                "CurveLend", 
                bytes4(keccak256("asset()")), 
                bytes4(keccak256("collateral_token()"))
            )
        );
        _executeCore(
            address(pairDeployer), 
            abi.encodeWithSelector(
                ResupplyPairDeployer.addSupportedProtocol.selector, 
                "Fraxlend", 
                bytes4(keccak256("asset()")), 
                bytes4(keccak256("collateralContract()"))
            )
        );
        address pair1 = deployLendingPair(1, Constants.Mainnet.FRAXLEND_SFRXETH_FRAX, address(0), 0);
        console.log('pair deployed: fraxlend_sfrxeth_frax', pair1);
        writeAddressToJson("PAIR_FRAXLEND_SFRXETH_FRAX", pair1);
        address pair2 = deployLendingPair(0, Constants.Mainnet.CURVELEND_SFRAX_CRVUSD, Constants.Mainnet.CONVEX_BOOSTER, Constants.Mainnet.CURVELEND_SFRAX_CRVUSD_ID);
        console.log('pair deployed: curvelend_sfrax_crvusd', pair2);
        writeAddressToJson("PAIR_CURVELEND_SFRAX_CRVUSD", pair2);
    }

    function configurationStep1() public {
        _executeCore(address(pairDeployer), abi.encodeWithSelector(ResupplyPairDeployer.setCreationCode.selector, type(ResupplyPair).creationCode));
        _executeCore(address(registry), abi.encodeWithSelector(ResupplyRegistry.setVestManager.selector, address(vestManager)));
        _executeCore(address(registry), abi.encodeWithSelector(ResupplyRegistry.setTreasury.selector, address(treasury)));
        _executeCore(address(registry), abi.encodeWithSelector(ResupplyRegistry.setStaker.selector, address(staker)));
    }

    function configureProtocolContracts() public {
        _executeCore(address(govToken), abi.encodeWithSelector(GovToken.setMinter.selector, address(emissionsController), true));
        _executeCore(address(feeDeposit), abi.encodeWithSelector(feeDeposit.setOperator.selector, address(feeDepositController)));
        _executeCore(address(staker), abi.encodeWithSelector(IGovStaker.addReward.selector, address(stablecoin), address(rewardHandler), uint256(7 days)));
        _executeCore(address(debtReceiver), abi.encodeWithSelector(SimpleReceiver.setApprovedClaimer.selector, address(rewardHandler), true));
        _executeCore(address(insuranceEmissionsReceiver), abi.encodeWithSelector(SimpleReceiver.setApprovedClaimer.selector, address(rewardHandler), true));
        _executeCore(address(registry), abi.encodeWithSelector(ResupplyRegistry.setRedemptionHandler.selector, address(redemptionHandler)));
        _executeCore(address(registry), abi.encodeWithSelector(ResupplyRegistry.setLiquidationHandler.selector, address(liquidationHandler)));
        _executeCore(address(registry), abi.encodeWithSelector(ResupplyRegistry.setInsurancePool.selector, address(insurancePool)));
        _executeCore(address(registry), abi.encodeWithSelector(ResupplyRegistry.setFeeDeposit.selector, address(feeDeposit)));
        _executeCore(address(registry), abi.encodeWithSelector(ResupplyRegistry.setRewardHandler.selector, address(rewardHandler)));
        _executeCore(address(stablecoin), abi.encodeWithSelector(Stablecoin.setOperator.selector, address(registry), true));
    }

    function grantOperatorPermissions() public {
        // During protocol launch phase, we grant the guardian multisig permissions to set the voter
        _executeCore(
            core, 
            abi.encodeWithSelector(
                ICore.setOperatorPermissions.selector, 
                dev, 
                address(core),
                ICore.setVoter.selector,
                true,
                address(0)
            )
        );
        console.log("Granted permissions to set voter");
        // Allow the guardian multisig to update proposal descriptions
        _executeCore(
            core, 
            abi.encodeWithSelector(
                ICore.setOperatorPermissions.selector, 
                dev, 
                address(voter),
                IVoter.updateProposalDescription.selector,
                true,
                address(0)
            )
        );
        console.log("Granted permissions to update proposal descriptions");
    }
}
