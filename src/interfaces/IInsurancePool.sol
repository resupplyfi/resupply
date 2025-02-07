// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IInsurancePool{
    function burnAssets(uint256 _amount) external;
    function exit() external;
    function cancelExit() external;
    function emissionsReceiver() external view returns(address);
    function maxBurnableAssets() external view returns(uint256);
}
