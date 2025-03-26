import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { Protocol, Prisma } from "script/protocol/ProtocolConstants.sol";
import { Guardian } from "src/dao/operators/Guardian.sol";
import { ITreasuryManager } from "src/interfaces/ITreasuryManager.sol";
import { ITreasury } from "src/interfaces/ITreasury.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { IGuardian } from "src/interfaces/IGuardian.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { TenderlyHelper } from "script/utils/TenderlyHelper.sol";
import { CreateXHelper } from "script/utils/CreateXHelper.sol";
import { CreateX } from "script/deploy/dependencies/DeploymentConfig.sol";
import { IPrismaCore } from "src/interfaces/IPrismaCore.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { console } from "forge-std/console.sol";
import { ISimpleReceiver } from "src/interfaces/ISimpleReceiver.sol";
import { ITreasuryManager } from "src/interfaces/ITreasuryManager.sol";
import { ICore } from "src/interfaces/ICore.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPrismaVoterProxy } from "src/interfaces/prisma/IPrismaVoterProxy.sol";

contract LaunchSetup3 is TenderlyHelper, CreateXHelper, BaseAction {
    address public constant deployer = Protocol.DEPLOYER;
    address public guardian;
    address public treasuryManager;
    address public grantRecipient1 = 0xf39Ed30Cc51b65392911fEA9F33Ec1ccceEe1ed5;
    address public grantRecipient2 = 0xEF1Ed12cecC1e76fdB63C6609f9E7548c26fA041;
    
    function run() public isBatch(deployer) {
        deployMode = DeployMode.PRODUCTION;

        transferGrant(grantRecipient1, 850e18);
        transferGrant(grantRecipient2, 850e18);
        deployGuardianAndConfigure();
        deployTreasuryManagerAndConfigure();
        acceptPrismaGovernance();
        configurePrismaVoter();
        if (deployMode == DeployMode.PRODUCTION) executeBatch(true, 16);
    }

    function configurePrismaVoter() public {
        _executeCore(
            Prisma.VOTER_PROXY,
            abi.encodeWithSelector(IPrismaVoterProxy.setVoteManager.selector, deployer)
        );

        IPrismaVoterProxy.GaugeWeightVote[] memory votes = new IPrismaVoterProxy.GaugeWeightVote[](4);
        votes[0] = IPrismaVoterProxy.GaugeWeightVote({
            gauge: 0x9A3dCece0968b8a94AfF643C9c72127a2C1D80dc, // PRISMA-ETH
            weight: 0
        });
        votes[1] = IPrismaVoterProxy.GaugeWeightVote({
            gauge: Protocol.REUSD_SCRVUSD_GAUGE,
            weight: 4000
        });
        votes[2] = IPrismaVoterProxy.GaugeWeightVote({
            gauge: Protocol.REUSD_SFRXUSD_GAUGE,
            weight: 4000
        });
        votes[3] = IPrismaVoterProxy.GaugeWeightVote({
            gauge: Protocol.WETH_RSUP_GAUGE,
            weight: 2000
        });
        addToBatch(
            Prisma.VOTER_PROXY,
            abi.encodeWithSelector(IPrismaVoterProxy.voteForGaugeWeights.selector, votes)
        );
    }

    function transferGrant(address _recipient, uint256 _amount) public {
        _executeCore(
            Protocol.TREASURY,
            abi.encodeWithSelector(
                ITreasury.retrieveTokenExact.selector, 
                Protocol.GOV_TOKEN,
                _recipient,
                _amount
            )
        );
        require(IERC20(Protocol.GOV_TOKEN).balanceOf(_recipient) >= _amount, "Grant not transferred");
    }

    function deployGuardianAndConfigure() public {
        // 1 Deploy Guardian
        // 2 Set permissions
        // 3 Set guardian role
        bytes32 salt = CreateX.SALT_OPERATOR_GUARDIAN;
        bytes memory constructorArgs = abi.encode(
            Protocol.CORE,
            Protocol.REGISTRY
        );
        bytes memory bytecode = abi.encodePacked(vm.getCode("Guardian.sol:Guardian"), constructorArgs);
        addToBatch(
            address(createXFactory),
            encodeCREATE3Deployment(salt, bytecode)
        );
        guardian = computeCreate3AddressFromSaltPreimage(salt, deployer, true, false);
        console.log("Guardian deployed at", guardian);
        require(guardian.code.length > 0, "deployment failed");
        
        setGuardianPermissions(deployer, false);
        setGuardianPermissions(guardian, true);

        // Set guardian
        _executeCore(
            guardian,
            abi.encodeWithSelector(
                IGuardian.setGuardian.selector,
                deployer
            )
        );
        require(IGuardian(guardian).guardian() == deployer, "Guardian guardian not set");
    }

    function deployTreasuryManagerAndConfigure() public {
        // 1 Deploy TreasuryManager
        // 2 Set permissions
        // 3 Set treasury manager role
        bytes32 salt = CreateX.SALT_OPERATOR_TREASURY_MANAGER;
        bytes memory constructorArgs = abi.encode(
            Protocol.CORE,
            Protocol.TREASURY
        );
        bytes memory bytecode = abi.encodePacked(vm.getCode("TreasuryManager.sol:TreasuryManager"), constructorArgs);
        addToBatch(
            address(createXFactory),
            encodeCREATE3Deployment(salt, bytecode)
        );
        treasuryManager = computeCreate3AddressFromSaltPreimage(salt, deployer, true, false);
        console.log("TreasuryManager deployed at", treasuryManager);
        require(treasuryManager.code.length > 0, "deployment failed");
        
        setTreasuryManagerPermissions(deployer, false); // revoke deployer permissions
        setTreasuryManagerPermissions(treasuryManager, true); // grant permissions to treasury manager operator

        // Set manager
        _executeCore(
            treasuryManager,
            abi.encodeWithSelector(
                ITreasuryManager.setManager.selector,
                deployer
            )
        );
        require(ITreasuryManager(treasuryManager).manager() == deployer, "TreasuryManager manager not set");

        // Set lp incentives receiver
        addToBatch(
            treasuryManager,
            abi.encodeWithSelector(ITreasuryManager.setLpIncentivesReceiver.selector, Protocol.LIQUIDITY_INCENTIVES_RECEIVER)
        );

        // Set approved claimers
        _executeCore(
            Protocol.LIQUIDITY_INCENTIVES_RECEIVER,
            abi.encodeWithSelector(ISimpleReceiver.setApprovedClaimer.selector, treasuryManager, true)
        );
    }

    function setTreasuryManagerPermissions(address _caller, bool _approve) internal {
        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = ITreasury.retrieveToken.selector;
        selectors[1] = ITreasury.retrieveTokenExact.selector;
        selectors[2] = ITreasury.retrieveETH.selector;
        selectors[3] = ITreasury.retrieveETHExact.selector;
        selectors[4] = ITreasury.setTokenApproval.selector;
        selectors[5] = ITreasury.execute.selector;
        selectors[6] = ITreasury.safeExecute.selector;
        for (uint256 i = 0; i < selectors.length; i++) {
            setOperatorPermissions(
                selectors[i],
                _caller,
                Protocol.TREASURY,
                _approve,
                address(0)
            );
        }
        if (_approve) {
            // Transfer token from prisma fee receiver
            setOperatorPermissions(
                bytes4(keccak256("transferToken(address,address,uint256)")),
                treasuryManager,
                Prisma.FEE_RECEIVER,
                true,
                address(0)
            );
            setOperatorPermissions(
                bytes4(keccak256("setTokenApproval(address,address,uint256)")),
                treasuryManager,
                Prisma.FEE_RECEIVER,
                true,
                address(0)
            );
            (
                bool p1, bool p2, bool p3, bool p4, bool p5, bool p6, bool p7, bool p8, bool p9
            ) = ITreasuryManager(treasuryManager).viewPermissions();
            require(p1 && p2 && p3 && p4 && p5 && p6 && p7 && p8 && p9, "TreasuryManager permissions not set");
        }
        
    }

    function setGuardianPermissions(address _caller, bool _approve) internal {
        // Cancel proposals
        setOperatorPermissions(
            IVoter.cancelProposal.selector,
            _caller,
            Protocol.VOTER,
            _approve,
            address(0)
        );
        // Update proposal description
        setOperatorPermissions(
            IVoter.updateProposalDescription.selector,
            _caller,
            Protocol.VOTER,
            _approve,
            address(0)
        );
        // Set address in registry
        setOperatorPermissions(
            IResupplyRegistry.setAddress.selector,
            _caller,
            Protocol.REGISTRY,
            _approve,
            address(0)
        );
        // Set address in registry
        setOperatorPermissions(
            ICore.setVoter.selector,
            _caller,
            Protocol.CORE,
            _approve,
            address(0)
        );
        // Pause pairs (any address)
        if (_approve) { // Skip revoke on this permission
            setOperatorPermissions(
                IResupplyPair.pause.selector,
                _caller,
                address(0),
                _approve,
                address(0)
            );
            (
                bool p1, bool p2, bool p3, bool p4, bool p5
            ) = IGuardian(guardian).viewPermissions();
            require(p1 && p2 && p3 && p4 && p5, "Guardian permissions not set");
        }
    }

    function acceptPrismaGovernance() public {
        IPrismaCore prismaCore = IPrismaCore(Prisma.PRISMA_CORE);
        _executeCore(
            address(prismaCore),
            abi.encodeWithSelector(
                IPrismaCore.acceptTransferOwnership.selector
            )
        );
        require(prismaCore.owner() == core, "PrismaCore owner not set");
    }
}