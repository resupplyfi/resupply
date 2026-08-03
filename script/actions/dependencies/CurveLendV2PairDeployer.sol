// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Mainnet, Protocol } from "src/Constants.sol";
import { IConvexStaking } from "src/interfaces/convex/IConvexStaking.sol";
import { ICurveLendV2Factory, ICurveLendV2Vault } from "src/interfaces/curve/ICurveLendV2Factory.sol";
import { IResupplyPairDeployer } from "src/interfaces/IResupplyPairDeployer.sol";

library CurveLendV2PairDeployer {
    uint256 private constant VAULT_TYPE = 1;
    bytes32 private constant FACTORY_VERSION = keccak256("2.0.0");

    function getDeployment(
        IResupplyPairDeployer pairDeployer,
        address vault,
        uint256 convexPid
    ) internal view returns (address pair, bytes memory data) {
        ICurveLendV2Factory.Market memory factoryMarket = _validate(vault, convexPid);
        require(factoryMarket.vault == vault, "LLv2 factory vault mismatch");

        (address borrowedToken, address collateralToken) = pairDeployer
            .getBorrowAndCollateralTokens(Protocol.PROTOCOL_ID_CURVE_V2, vault);
        require(
            borrowedToken == factoryMarket.borrowedToken,
            "Unexpected pair deployer borrowed token"
        );
        require(
            collateralToken == factoryMarket.collateralToken,
            "Unexpected pair deployer collateral token"
        );

        pair = pairDeployer.predictPairAddress(
            Protocol.PROTOCOL_ID_CURVE_V2,
            vault,
            Mainnet.CONVEX_BOOSTER,
            convexPid
        );
        data = abi.encodeWithSelector(
            pairDeployer.deployWithDefaultConfig.selector,
            Protocol.PROTOCOL_ID_CURVE_V2,
            vault,
            Mainnet.CONVEX_BOOSTER,
            convexPid
        );
    }

    function validate(address vault, uint256 convexPid) internal view {
        ICurveLendV2Factory.Market memory factoryMarket = _validate(vault, convexPid);
        require(factoryMarket.vault == vault, "LLv2 factory vault mismatch");
    }

    function _validate(
        address vault,
        uint256 convexPid
    ) private view returns (ICurveLendV2Factory.Market memory factoryMarket) {
        address factoryAddress = ICurveLendV2Vault(vault).factory();
        require(_isRecognizedFactory(factoryAddress), "Unrecognized LLv2 factory");

        ICurveLendV2Factory factory = ICurveLendV2Factory(factoryAddress);
        require(
            keccak256(bytes(factory.version())) == FACTORY_VERSION,
            "Unsupported LLv2 factory version"
        );

        (uint256 marketIndex, uint256 contractType) = factory.check_contract(vault);
        require(contractType == VAULT_TYPE, "LLv2 asset is not a factory vault");

        factoryMarket = factory.markets(marketIndex);

        (address lpToken,,,,, bool shutdown) =
            IConvexStaking(Mainnet.CONVEX_BOOSTER).poolInfo(convexPid);
        require(lpToken == vault, "Staking pool collateral mismatch");
        require(!shutdown, "Staking pool is shutdown");
    }

    /// @dev Add future reviewed LLv2 factories here before using them in proposals.
    function _isRecognizedFactory(address factory) private pure returns (bool) {
        return factory == Mainnet.CURVE_LEND_V2_FACTORY;
    }
}
