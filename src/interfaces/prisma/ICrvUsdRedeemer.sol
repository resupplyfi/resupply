// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ICrvUsdRedeemer {
    function CRVUSD() external view returns (IERC20);
    function RESUPPLY_TREASURY() external view returns (address);
    function psm() external view returns (address);
    function debtToken() external view returns (IERC20);

    function redeem() external returns (uint256);
    function getPsmBalance() external view returns (uint256);
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external;

    // TM interface stubs
    function fetchPrice() external view returns (uint256);
    function setAddresses(address, address, address) external;
    function setParameters(uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256) external;
    function collateralToken() external view returns (address);
    function getTroveStatus(address) external view returns (uint256);
    function getTroveCollAndDebt(address) external view returns (uint256, uint256);
    function getEntireDebtAndColl(address) external view returns (uint256, uint256, uint256, uint256);
    function getEntireSystemColl() external view returns (uint256);
    function getEntireSystemDebt() external view returns (uint256);
    function getEntireSystemBalances() external view returns (uint256, uint256, uint256);
    function getNominalICR(address) external view returns (uint256);
    function getCurrentICR(address) external view returns (uint256);
    function getTotalActiveCollateral() external view returns (uint256);
    function getTotalActiveDebt() external view returns (uint256);
    function getPendingCollAndDebtRewards(address) external view returns (uint256, uint256);
    function hasPendingRewards(address) external view returns (bool);
    function getRedemptionRate() external view returns (uint256);
    function getRedemptionRateWithDecay(uint256) external view returns (uint256);
    function getRedemptionFeeWithDecay(address) external view returns (uint256);
    function getBorrowingRate(address) external view returns (uint256);
    function getBorrowingRateWithDecay(address) external view returns (uint256);
    function getBorrowingFeeWithDecay(address) external view returns (uint256);
}
