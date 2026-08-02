// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Mainnet, Protocol } from "src/Constants.sol";
import { IConvexStaking } from "src/interfaces/convex/IConvexStaking.sol";
import { ICurveLendV2Factory } from "src/interfaces/curve/ICurveLendV2Factory.sol";
import { IResupplyPairDeployer } from "src/interfaces/IResupplyPairDeployer.sol";
import { ResupplyPairDeployer } from "src/protocol/ResupplyPairDeployer.sol";

library CurveLendV2PairDeployer {
    uint256 private constant VAULT_TYPE = 1;
    bytes32 private constant FACTORY_VERSION = keccak256("2.0.0");

    struct Market {
        address factory;
        address vault;
        address borrowedToken;
        address collateralToken;
        uint256 convexPid;
    }

    function getDeployment(
        IResupplyPairDeployer pairDeployer,
        Market memory market,
        uint256 initialBorrowLimit
    ) internal view returns (address pair, bytes memory data) {
        validate(market);

        (address borrowedToken, address collateralToken) = pairDeployer
            .getBorrowAndCollateralTokens(Protocol.PROTOCOL_ID_CURVE_V2, market.vault);
        require(borrowedToken == market.borrowedToken, "Unexpected pair deployer borrowed token");
        require(collateralToken == market.collateralToken, "Unexpected pair deployer collateral token");

        ResupplyPairDeployer.ConfigData memory config =
            ResupplyPairDeployer(address(pairDeployer)).defaultConfigData();
        bytes memory configData = abi.encode(
            market.vault,
            config.oracle,
            config.rateCalculator,
            config.maxLTV,
            initialBorrowLimit,
            config.liquidationFee,
            config.mintFee,
            config.protocolRedemptionFee
        );

        pair = pairDeployer.predictPairAddress(
            Protocol.PROTOCOL_ID_CURVE_V2,
            configData,
            Mainnet.CONVEX_BOOSTER,
            market.convexPid
        );
        data = abi.encodeWithSelector(
            pairDeployer.deploy.selector,
            Protocol.PROTOCOL_ID_CURVE_V2,
            configData,
            Mainnet.CONVEX_BOOSTER,
            market.convexPid
        );
    }

    function validate(Market memory market) internal view {
        require(_isRecognizedFactory(market.factory), "Unrecognized LLv2 factory");

        ICurveLendV2Factory factory = ICurveLendV2Factory(market.factory);
        require(
            keccak256(bytes(factory.version())) == FACTORY_VERSION,
            "Unsupported LLv2 factory version"
        );

        (uint256 marketIndex, uint256 contractType) = factory.check_contract(market.vault);
        require(contractType == VAULT_TYPE, "LLv2 asset is not a factory vault");

        ICurveLendV2Factory.Market memory factoryMarket = factory.markets(marketIndex);
        require(factoryMarket.vault == market.vault, "LLv2 factory vault mismatch");
        require(factoryMarket.borrowedToken == market.borrowedToken, "Unexpected LLv2 borrowed token");
        require(factoryMarket.collateralToken == market.collateralToken, "Unexpected LLv2 collateral token");

        (address lpToken,,,,, bool shutdown) =
            IConvexStaking(Mainnet.CONVEX_BOOSTER).poolInfo(market.convexPid);
        require(lpToken == market.vault, "Staking pool collateral mismatch");
        require(!shutdown, "Staking pool is shutdown");
    }

    /// @dev Add future reviewed LLv2 factories here before using them in proposals.
    function _isRecognizedFactory(address factory) private pure returns (bool) {
        return factory == Mainnet.CURVE_LEND_V2_FACTORY;
    }
}
