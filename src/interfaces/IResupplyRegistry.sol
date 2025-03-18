// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IResupplyRegistry {
    event AddPair(address pairAddress);
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event SetDeployer(address deployer, bool _bool);
    event DefaultSwappersSet(address[] addresses);
    event EntryUpdated(string indexed key, address indexed addr);
    event WithdrawTo(address indexed user, uint256 amount);

    // Protected keys
    function LIQUIDATION_HANDLER() external pure returns (string memory);
    function FEE_DEPOSIT() external pure returns (string memory);
    function REDEMPTION_HANDLER() external pure returns (string memory);
    function INSURANCE_POOL() external pure returns (string memory);
    function REWARD_HANDLER() external pure returns (string memory);
    function TREASURY() external pure returns (string memory);
    function STAKER() external pure returns (string memory);
    function L2_MANAGER() external pure returns (string memory);
    function VEST_MANAGER() external pure returns (string memory);

    // Other public functions
    function token() external view returns (address);
    function govToken() external view returns (address);
    function getAddress(string memory key) external view returns (address);
    function getAllKeys() external view returns (string[] memory);
    function getAllAddresses() external view returns (address[] memory);
    function getProtectedKeys() external pure returns (string[] memory);
    function keyExists(string memory) external view returns (bool);
    function hashToKey(bytes32) external view returns (string memory);
    function setAddress(string memory key, address addr) external;
    function acceptOwnership() external;
    function addPair(address _pairAddress) external;
    function registeredPairs(uint256) external view returns (address);
    function pairsByName(string memory) external view returns (address);
    function defaultSwappersLength() external view returns (uint256);
    function registeredPairsLength() external view returns (uint256);
    function getAllPairAddresses() external view returns (address[] memory _deployedPairsArray);
    function getAllDefaultSwappers() external view returns (address[] memory _defaultSwappers);
    function owner() external view returns (address);
    function pendingOwner() external view returns (address);
    function renounceOwnership() external;
    function transferOwnership(address newOwner) external;
    function claimFees(address _pair) external;
    function claimRewards(address _pair) external;
    function claimInsuranceRewards() external;
    function withdrawTo(address _asset, uint256 _amount, address _to) external;
    function mint(address receiver, uint256 amount) external;
    function burn(address target, uint256 amount) external;
    function liquidationHandler() external view returns(address);
    function feeDeposit() external view returns(address);
    function redemptionHandler() external view returns(address);
    function rewardHandler() external view returns(address);
    function insurancePool() external view returns(address);
    function setRewardClaimer(address _newAddress) external;
    function setRedemptionHandler(address _newAddress) external;
    function setFeeDeposit(address _newAddress) external;
    function setLiquidationHandler(address _newAddress) external;
    function setInsurancePool(address _newAddress) external;
    function setStaker(address _newAddress) external;
    function setTreasury(address _newAddress) external;
    function staker() external view returns(address);
    function treasury() external view returns(address);
    function l2manager() external view returns(address);
    function setRewardHandler(address _newAddress) external;
    function setVestManager(address _newAddress) external;
    function setDefaultSwappers(address[] memory _swappers) external;
    function collateralId(address _collateral) external view returns(uint256);

    error NameMustBeUnique();
    error ProtectedKey(string key);
}