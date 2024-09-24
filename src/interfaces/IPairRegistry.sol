// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

interface IPairRegistry {
    event AddPair(address pairAddress);
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event SetDeployer(address deployer, bool _bool);

    function acceptOwnership() external;

    function addPair(address _pairAddress) external;

    function deployedPairsArray(uint256) external view returns (address);

    function deployedPairsByName(string memory) external view returns (address);

    function defaultSwappersLength() external view returns (uint256);
    function deployedPairsLength() external view returns (uint256);

    function getAllPairAddresses() external view returns (address[] memory _deployedPairsArray);
    
    function getAllDefaultSwappers() external view returns (address[] memory _defaultSwappers);

    function owner() external view returns (address);

    function pendingOwner() external view returns (address);

    function renounceOwnership() external;

    function transferOwnership(address newOwner) external;

    function claimFees(address _pair) external;
    function withdrawTo(address _asset, uint256 _amount, address _to) external;
    function getMaxMintable(address pair) external view returns(uint256);
    function mint( address receiver, uint256 amount) external;
    function burn( address target, uint256 amount) external;
    function liquidationHandler() external view returns(address);
    function feeDeposit() external view returns(address);
    function redeemer() external view returns(address);
}
