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
    // Functions: External Methods
    // ============================================================================================

    event SetLiquidationHandler(address oldAddress, address newAddress);

    function setLiquidationHandler(address _newAddress) external onlyOwner{
        emit SetLiquidationHandler(liquidationHandler, _newAddress);
        liquidationHandler = _newAddress;
    }

    event SetFeeDeposit(address oldAddress, address newAddress);

    function setFeeDeposit(address _newAddress) external onlyOwner{
        emit SetFeeDeposit(feeDeposit, _newAddress);
        feeDeposit = _newAddress;
    }

    event SetRedemptionHandler(address oldAddress, address newAddress);

    function setRedemptionHandler(address _newAddress) external onlyOwner{
        emit SetRedemptionHandler(redemptionHandler, _newAddress);
        redemptionHandler = _newAddress;
    }

    event SetInsurancePool(address oldAddress, address newAddress);

    function setInsurancePool(address _newAddress) external onlyOwner{
        emit SetInsurancePool(insurancePool, _newAddress);
        insurancePool = _newAddress;
    }

    event SetRewardHandler(address oldAddress, address newAddress);

    function setRewardHandler(address _newAddress) external onlyOwner{
        emit SetRewardHandler(rewardHandler, _newAddress);
        rewardHandler = _newAddress;
    }

    event SetStaker(address oldAddress, address newAddress);

    function setStaker(address _newAddress) external onlyOwner{
        emit SetStaker(staker, _newAddress);
        staker = _newAddress;
    }

    event SetTreasury(address oldAddress, address newAddress);

    function setTreasury(address _newAddress) external onlyOwner{
        emit SetTreasury(treasury, _newAddress);
        treasury = _newAddress;
    }

    /// @notice The ```AddPair``` event is emitted when a new pair is added to the registry
    /// @param pairAddress The address of the pair
    event AddPair(address pairAddress);

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


    event DefaultSwappersSet(address[] addresses);

    /// @notice The ```setDefaultSwappers``` function is used to set default list of approved swappers
    /// @param _swappers The list of swappers to set as default allowed
    function setDefaultSwappers(address[] memory _swappers) external onlyOwner{
        defaultSwappers = _swappers;
        emit DefaultSwappersSet(_swappers);
    }

    function withdrawTo(address _asset, uint256 _amount, address _to) external onlyOwner{
        IERC20(_asset).safeTransfer(_to, _amount);
        emit WithdrawTo(_to, _amount);
    }

    function mint(address _receiver, uint256 _amount) external{
        //ensure caller is a registered pair
        require(pairsByName[IERC20Metadata(msg.sender).name()] == msg.sender, "!regPair");

        //ask minter to mint
        IMintable(token).mint(_receiver, _amount);
    }

    function claimFees(address _pair) external{
        IResupplyPair(_pair).withdrawFees();
    }

    function claimRewards(address _pair) external{
        //tell rewardHandler to process rewards
        IRewardHandler(rewardHandler).claimRewards(_pair);
    }

    function claimInsuranceRewards() external{
        //tell rewardHandler to process rewards for insurance pool
        IRewardHandler(rewardHandler).claimInsuranceRewards();
    }

    function getMaxMintable(address _pair) external view returns(uint256){
        return type(uint256).max;
    }

    // ============================================================================================
    // Errors
    // ============================================================================================

    error NameMustBeUnique();
    event WithdrawTo(address indexed user, uint256 amount);
}
