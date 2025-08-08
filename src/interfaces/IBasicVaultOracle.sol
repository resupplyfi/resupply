pragma solidity 0.8.30;

interface IBasicVaultOracle {
    function decimals() external pure returns (uint8);

    function getPrices(address _vault) external view returns (uint256 _price);

    function name() external view returns (string memory);

    function oracleType() external view returns (uint256);
}