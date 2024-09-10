// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

library FraxlendPairDeployerHelper {
    function __encodeConfigData(
        address _asset,
        address _collateral,
        address _oracle,
        uint32 _maxOracleDeviation,
        address _rateContract,
        uint64 _fullUtilizationRate,
        uint256 _maxLTV,
        uint256 _liquidationFee,
        uint256 _protocolLiquidationFee
    ) public pure returns (bytes memory _configData) {
        return
            abi.encode(
                _asset,
                _collateral,
                _oracle,
                _maxOracleDeviation,
                _rateContract,
                _fullUtilizationRate,
                _maxLTV,
                _liquidationFee,
                _protocolLiquidationFee
            );
    }

    function __encodeConfigData(
        address _asset,
        address _collateral,
        address _oracle,
        uint32 _maxOracleDeviation,
        address _rateContract,
        uint64 _fullUtilizationRate,
        uint256 _maxLTV,
        uint256 _liquidationFee,
        uint256 _protocolLiquidationFee,
        address _checkPointAddress
    ) public pure returns (bytes memory _configData) {
        return
            abi.encode(
                _asset,
                _collateral,
                _oracle,
                _maxOracleDeviation,
                _rateContract,
                _fullUtilizationRate,
                _maxLTV,
                _liquidationFee,
                _protocolLiquidationFee,
                _checkPointAddress
            );
    }
}
