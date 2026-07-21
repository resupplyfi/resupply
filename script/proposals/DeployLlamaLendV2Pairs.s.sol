// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Script } from "lib/forge-std/src/Script.sol";
import { console } from "lib/forge-std/src/console.sol";
import { IResupplyPairDeployer } from "src/interfaces/IResupplyPairDeployer.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { Mainnet, Protocol } from "src/Constants.sol";

interface ICurveLendV2Vault {
    function amm() external view returns (address);
    function asset() external view returns (address);
    function borrowed_token() external view returns (address);
    function collateral_token() external view returns (address);
    function controller() external view returns (address);
    function factory() external view returns (address);
}

interface ICurveLendV2Factory {
    function check_contract(address account) external view returns (uint256 marketIndex, uint256 contractType);
}

contract DeployLlamaLendV2Pairs is Script {
    string public constant DESCRIPTION = "Deploy and register Resupply pairs for Curve LlamaLend v2 sDOLA/crvUSD and sfrxUSD/crvUSD lender vaults";

    uint256 public constant CURVE_PROTOCOL_ID = Protocol.PROTOCOL_ID_CURVE;
    address public constant CURVE_LEND_V2_FACTORY = 0x8f6B56EC5ddF1F2691a1059f1D3cd97Ac9EaB0bd;
    address public constant SDOLA_VAULT = 0x2b5a321C3cb1F33e1ABECD047C2649D0b4C47eBa;
    address public constant SDOLA_COLLATERAL = 0xb45ad160634c528Cc3D2926d9807104FA3157305;
    address public constant SDOLA_CONTROLLER = 0xC77d97cF01737EB7aCE46cAb7cd9F60eC51a40c0;
    address public constant SDOLA_AMM = 0xbf6f64B741164c26023f97fAaEA8e02453c27442;

    address public constant SFRXUSD_VAULT = 0x3Da0F110079012387F47C6Fc6e878F10262E300a;
    address public constant SFRXUSD_COLLATERAL = 0xcf62F905562626CfcDD2261162a51fd02Fc9c5b6;
    address public constant SFRXUSD_CONTROLLER = 0x3cD4d86a2c65e57ce4b4121b67E2D2224BA41bbe;
    address public constant SFRXUSD_AMM = 0x63791be4985992580F84daE105bcc0e15C282d1F;

    IResupplyPairDeployer public constant pairDeployer = IResupplyPairDeployer(Protocol.PAIR_DEPLOYER_V2);
    IResupplyRegistry public constant registry = IResupplyRegistry(Protocol.REGISTRY);
    IVoter public constant voter = IVoter(Protocol.VOTER);

    function run() public {
        IVoter.Action[] memory actions = buildProposalCalldata();
        printCallData(actions);

        vm.startBroadcast();
        (, address proposer,) = vm.readCallers();
        uint256 proposalId = voter.createNewProposal(proposer, actions, DESCRIPTION);
        vm.stopBroadcast();

        console.log("Proposal created by:", proposer);
        console.log("Proposal ID:", proposalId);
    }

    function buildProposalCalldata() public view returns (IVoter.Action[] memory actions) {
        _validateDependencies();
        (address sdolaPair, address sfrxUsdPair) = getPredictedPairAddresses();

        require(sdolaPair.code.length == 0, "sDOLA pair already deployed");
        require(sfrxUsdPair.code.length == 0, "sfrxUSD pair already deployed");

        actions = new IVoter.Action[](4);
        actions[0] = _getDeployAction(SDOLA_VAULT);
        actions[1] = _getAddPairAction(sdolaPair);
        actions[2] = _getDeployAction(SFRXUSD_VAULT);
        actions[3] = _getAddPairAction(sfrxUsdPair);
    }

    function getPredictedPairAddresses() public view returns (address sdolaPair, address sfrxUsdPair) {
        sdolaPair = pairDeployer.predictPairAddress(CURVE_PROTOCOL_ID, SDOLA_VAULT, address(0), 0);
        sfrxUsdPair = pairDeployer.predictPairAddress(CURVE_PROTOCOL_ID, SFRXUSD_VAULT, address(0), 0);
    }

    function _getDeployAction(address vault) internal pure returns (IVoter.Action memory action) {
        action = IVoter.Action({ target: Protocol.PAIR_DEPLOYER_V2, data: abi.encodeWithSelector(IResupplyPairDeployer.deployWithDefaultConfig.selector, CURVE_PROTOCOL_ID, vault, address(0), 0) });
    }

    function _getAddPairAction(address pair) internal pure returns (IVoter.Action memory action) {
        // Voter executes every governance action through Core.execute. Calling PairAdder here would
        // attempt a nested Core.execute and revert under Core's reentrancy guard.
        action = IVoter.Action({ target: Protocol.REGISTRY, data: abi.encodeWithSelector(IResupplyRegistry.addPair.selector, pair) });
    }

    function _validateDependencies() internal view {
        require(registry.getAddress("PAIR_DEPLOYER") == Protocol.PAIR_DEPLOYER_V2, "unexpected pair deployer");
        require(pairDeployer.owner() == Protocol.CORE, "unexpected pair deployer owner");
        require(Mainnet.CRVUSD_ERC20.code.length > 0, "crvUSD not deployed");

        _validateVault(SDOLA_VAULT, SDOLA_COLLATERAL, SDOLA_CONTROLLER, SDOLA_AMM, 0);
        _validateVault(SFRXUSD_VAULT, SFRXUSD_COLLATERAL, SFRXUSD_CONTROLLER, SFRXUSD_AMM, 1);
    }

    function _validateVault(address vaultAddress, address expectedCollateral, address expectedController, address expectedAmm, uint256 expectedMarketIndex) internal view {
        ICurveLendV2Vault vault = ICurveLendV2Vault(vaultAddress);
        require(vault.factory() == CURVE_LEND_V2_FACTORY, "unexpected Curve factory");
        require(vault.asset() == Mainnet.CRVUSD_ERC20, "unexpected vault asset");
        require(vault.borrowed_token() == Mainnet.CRVUSD_ERC20, "unexpected borrowed token");
        require(vault.collateral_token() == expectedCollateral, "unexpected collateral token");
        require(vault.controller() == expectedController, "unexpected controller");
        require(vault.amm() == expectedAmm, "unexpected AMM");

        (uint256 marketIndex, uint256 contractType) = ICurveLendV2Factory(CURVE_LEND_V2_FACTORY).check_contract(vaultAddress);
        require(marketIndex == expectedMarketIndex, "unexpected Curve market index");
        require(contractType == 1, "vault not registered in Curve factory");
    }

    function printCallData(IVoter.Action[] memory actions) public view {
        (address sdolaPair, address sfrxUsdPair) = getPredictedPairAddresses();
        console.log("sDOLA pair:", sdolaPair);
        console.log("sfrxUSD pair:", sfrxUsdPair);

        for (uint256 i = 0; i < actions.length; i++) {
            console.log("Action", i + 1);
            console.log(actions[i].target);
            console.logBytes(actions[i].data);
        }
    }
}
