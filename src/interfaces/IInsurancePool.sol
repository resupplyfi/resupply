// SPDX-License-Identifier: ISC
pragma solidity >=0.8.19;

interface IInsurancePool{
    function burnAssets(uint256 _amount) external;
    function exit() external;
    function cancelExit() external;
    function emissionsReceiver() external view returns(address);
}
