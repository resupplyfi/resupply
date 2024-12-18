// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

// ====================================================================
// |     ______                   _______                             |
// |    / _____________ __  __   / ____(_____  ____ _____  ________   |
// |   / /_  / ___/ __ `| |/_/  / /_  / / __ \/ __ `/ __ \/ ___/ _ \  |
// |  / __/ / /  / /_/ _>  <   / __/ / / / / / /_/ / / / / /__/  __/  |
// | /_/   /_/   \__,_/_/|_|  /_/   /_/_/ /_/\__,_/_/ /_/\___/\___/   |
// |                                                                  |
// ====================================================================
// ====================== ResupplyPairRegistry ========================
// ====================================================================
// Frax Finance: https://github.com/FraxFinance

// Primary Author
// Drake Evans: https://github.com/DrakeEvans

// Reviewers
// Dennis: https://github.com/denett
// Rich Gee: https://github.com/zer0blockchain

// ====================================================================

import { CoreOwnable } from '../dependencies/CoreOwnable.sol';
import { IResupplyPair } from "../interfaces/IResupplyPair.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "../libraries/SafeERC20.sol";
import { IMintable } from "../interfaces/IMintable.sol";
import { IRewardHandler } from "../interfaces/IRewardHandler.sol";

contract ResupplyRegistry is CoreOwnable{
    using SafeERC20 for IERC20;

    mapping(string => address) private keyToAddress;

    string[] private keys;

    mapping(string => bool) public keyExists; // to prevent duplicates
    mapping(bytes32 => string) public hashToKey;

    address public immutable token;
    address public immutable govToken;
    /// @notice List of the addresses of all deployed Pairs
    address[] public registeredPairs;

    /// @notice name => deployed address
    mapping(string => address) public pairsByName;

    // Default swappers
    address[] public defaultSwappers;
    // protocol contracts
    address public liquidationHandler;
    address public feeDeposit;
    address public redemptionHandler;
    address public rewardHandler;
    address public insurancePool;
    address public staker;
    address public treasury;

    constructor(address _core, address _token, address _govToken) CoreOwnable(_core){
        token = _token;
        govToken = _govToken;
    }

    event AddPair(address pairAddress);
    event DefaultSwappersSet(address[] addresses);
    event EntryUpdated(string indexed key, address indexed addr);
    event WithdrawTo(address indexed user, uint256 amount);

    // ============================================================================================
    // Functions: View Functions
    // ============================================================================================

    /// @notice The ```registeredPairsLength``` function returns the length of the registeredPairs
    /// @return length of array
    function registeredPairsLength() external view returns (uint256) {
        return registeredPairs.length;
    }

    /// @notice The ```getAllPairAddresses``` function returns an array of all deployed pairs
    /// @return _registeredPairs The array of pairs deployed
    function getAllPairAddresses() external view returns (address[] memory _registeredPairs) {
        _registeredPairs = registeredPairs;
    }

    // ============================================================================================
    // Functions: Core Asset Registry
    // ============================================================================================

    function setLiquidationHandler(address _newAddress) external onlyOwner{
        liquidationHandler = _newAddress;
        _setAddress(_newAddress, "LIQUIDATION_HANDLER", keccak256(bytes("LIQUIDATION_HANDLER")));
    }

    function setFeeDeposit(address _newAddress) external onlyOwner{
        feeDeposit = _newAddress;
        _setAddress(_newAddress, "FEE_DEPOSIT", keccak256(bytes("FEE_DEPOSIT")));
    }

    function setRedemptionHandler(address _newAddress) external onlyOwner{
        redemptionHandler = _newAddress;
        _setAddress(_newAddress, "REDEMPTION_HANDLER", keccak256(bytes("REDEMPTION_HANDLER")));
    }

    function setInsurancePool(address _newAddress) external onlyOwner{
        insurancePool = _newAddress;
        _setAddress(_newAddress, "INSURANCE_POOL", keccak256(bytes("INSURANCE_POOL")));
    }

    function setRewardHandler(address _newAddress) external onlyOwner{
        rewardHandler = _newAddress;
        _setAddress(_newAddress, "REWARD_HANDLER", keccak256(bytes("REWARD_HANDLER")));
    }

    function setStaker(address _newAddress) external onlyOwner{
        staker = _newAddress;
        _setAddress(_newAddress, "STAKER", keccak256(bytes("STAKER")));
    }

    function setTreasury(address _newAddress) external onlyOwner{
        treasury = _newAddress;
        _setAddress(_newAddress, "TREASURY", keccak256(bytes("TREASURY")));
    }

    /// @notice The ```addPair``` function adds a pair to the registry and ensures a unique name
    /// @param _pairAddress The address of the pair
    function addPair(address _pairAddress) external onlyOwner{
        // Add pair to the global list
        registeredPairs.push(_pairAddress);

        // Pull name, ensure uniqueness and add to the name mapping
        string memory _name = IERC20Metadata(_pairAddress).name();
        if (pairsByName[_name] != address(0)) revert NameMustBeUnique();
        pairsByName[_name] = _pairAddress;

        // Set additional values for ResupplyPair
        IResupplyPair _pair = IResupplyPair(_pairAddress);
        address[] memory _defaultSwappers = defaultSwappers;
        for (uint256 i = 0; i < _defaultSwappers.length; i++) {
            _pair.setSwapper(_defaultSwappers[i], true);
        }

        emit AddPair(_pairAddress);
    }

    /// @notice The ```setDefaultSwappers``` function is used to set default list of approved swappers
    /// @param _swappers The list of swappers to set as default allowed
    function setDefaultSwappers(address[] memory _swappers) external onlyOwner{
        defaultSwappers = _swappers;
        emit DefaultSwappersSet(_swappers);
    }

    // ============================================================================================
    // Functions: Key Value Asset Registry
    // ============================================================================================


    /// @notice Generic address setter for the registry
    /// @dev Cannot use for protected keys, since they are already assigned to specific variables
    /// @param key The key to associate with the address
    /// @param addr The address to store in the registry
    function setAddress(string memory key, address addr) public onlyOwner {
        bytes32 keyHash = keccak256(bytes(key));
        // Check if key is protected
        string[] memory protectedKeys = getProtectedKeys();
        for (uint256 i = 0; i < protectedKeys.length; i++) {
            require(keyHash != keccak256(bytes(protectedKeys[i])), "Protected key");
        }
        _setAddress(addr, key, keyHash);
    }

    function _setAddress(address addr, string memory key, bytes32 keyHash) internal {
        require(bytes(key).length > 0, "Key cannot be empty");
        require(addr != address(0), "Address cannot be zero");
        if (!keyExists[key]) {
            hashToKey[keyHash] = key;
            keys.push(key);
            keyExists[key] = true;
        }
        keyToAddress[key] = addr;
        emit EntryUpdated(key, addr);
    }

    function getAddress(string memory key) public view returns (address) {
        return keyToAddress[key];
    }

    function getAllKeys() public view returns (string[] memory) {
        return keys;
    }

    function getAllAddresses() public view returns (address[] memory) {
        address[] memory addresses = new address[](keys.length);
        for (uint i = 0; i < keys.length; i++) {
            addresses[i] = keyToAddress[keys[i]];
        }
        return addresses;
    }

    function getProtectedKeys() public pure returns (string[] memory) {
        string[] memory _protectedKeys = new string[](7);
        _protectedKeys[0] = "LIQUIDATION_HANDLER";
        _protectedKeys[1] = "FEE_DEPOSIT";
        _protectedKeys[2] = "REDEMPTION_HANDLER";
        _protectedKeys[3] = "INSURANCE_POOL";
        _protectedKeys[4] = "REWARD_HANDLER";
        _protectedKeys[5] = "TREASURY";
        _protectedKeys[6] = "STAKER";
        return _protectedKeys;
    }

    // ============================================================================================
    // Functions: Operations
    // ============================================================================================

    function withdrawTo(address _asset, uint256 _amount, address _to) external onlyOwner {
        IERC20(_asset).safeTransfer(_to, _amount);
        emit WithdrawTo(_to, _amount);
    }

    function mint(address _receiver, uint256 _amount) external {
        require(pairsByName[IERC20Metadata(msg.sender).name()] == msg.sender, "!regPair");
        IMintable(token).mint(_receiver, _amount);
    }

    function claimFees(address _pair) external {
        IResupplyPair(_pair).withdrawFees();
    }

    function claimRewards(address _pair) external {
        IRewardHandler(rewardHandler).claimRewards(_pair);
    }

    function claimInsuranceRewards() external {
        IRewardHandler(rewardHandler).claimInsuranceRewards();
    }

    function getMaxMintable(address _pair) external view returns(uint256) {
        return type(uint256).max;
    }

    // ============================================================================================
    // Errors
    // ============================================================================================

    error NameMustBeUnique();
    error CircuitBreakerOnly();
    error ProtectedKey(string key);
}
