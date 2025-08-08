pragma solidity 0.8.28;

interface IUnderlyingOracle {
    function crvusd() external view returns (address);

    function crvusd_oracle() external view returns (address);

    function decimals() external pure returns (uint8);

    function frxusd() external view returns (address);

    function frxusd_oracle() external view returns (address);

    function getPrices(address _token) external view returns (uint256 _price);

    function name() external view returns (string memory);

    function oracleType() external view returns (uint256);
}