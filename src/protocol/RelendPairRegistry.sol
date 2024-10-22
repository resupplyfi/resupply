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
// ====================== FraxlendPairRegistry ========================
// ====================================================================
// Frax Finance: https://github.com/FraxFinance

// Primary Author
// Drake Evans: https://github.com/DrakeEvans

// Reviewers
// Dennis: https://github.com/denett
// Rich Gee: https://github.com/zer0blockchain

// ====================================================================

import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IFraxlendPair } from "../interfaces/IFraxlendPair.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "../libraries/SafeERC20.sol";
import { IMintable } from "../interfaces/IMintable.sol";
import { IRewardHandler } from "../interfaces/IRewardHandler.sol";

contract RelendPairRegistry is Ownable2Step{
    using SafeERC20 for IERC20;

    address public immutable token;

    /// @notice List of the addresses of all deployed Pairs
    address[] public deployedPairsArray;

    /// @notice name => deployed address
    mapping(string => address) public deployedPairsByName;

    // Default swappers
    address[] public defaultSwappers;
    // protocol contracts
    address public circuitBreakerAddress;
    address public liquidationHandler;
    address public feeDeposit;
    address public redeemer;
    address public rewardHandler;
    address public insurancePool;

    constructor(address _token, address _owner) Ownable2Step(){
        token = _token;
        _transferOwnership(_owner);
    }

    // ============================================================================================
    // Functions: View Functions
    // ============================================================================================

    /// @notice The ```deployedPairsLength``` function returns the length of the deployedPairsArray
    /// @return length of array
    function deployedPairsLength() external view returns (uint256) {
        return deployedPairsArray.length;
    }

    /// @notice The ```getAllPairAddresses``` function returns an array of all deployed pairs
    /// @return _deployedPairsArray The array of pairs deployed
    function getAllPairAddresses() external view returns (address[] memory _deployedPairsArray) {
        _deployedPairsArray = deployedPairsArray;
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

    event SetRedeemer(address oldAddress, address newAddress);

    function setRedeemer(address _newAddress) external onlyOwner{
        emit SetRedeemer(redeemer, _newAddress);
        redeemer = _newAddress;
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

    /// @notice The ```AddPair``` event is emitted when a new pair is added to the registry
    /// @param pairAddress The address of the pair
    event AddPair(address pairAddress);

    /// @notice The ```addPair``` function adds a pair to the registry and ensures a unique name
    /// @param _pairAddress The address of the pair
    function addPair(address _pairAddress) external onlyOwner{

        // Add pair to the global list
        deployedPairsArray.push(_pairAddress);

        // Pull name, ensure uniqueness and add to the name mapping
        string memory _name = IERC20Metadata(_pairAddress).name();
        if (deployedPairsByName[_name] != address(0)) revert NameMustBeUnique();
        deployedPairsByName[_name] = _pairAddress;

        // Set additional values for FraxlendPair
        IFraxlendPair _fraxlendPair = IFraxlendPair(_pairAddress);
        address[] memory _defaultSwappers = defaultSwappers;
        for (uint256 i = 0; i < _defaultSwappers.length; i++) {
            _fraxlendPair.setSwapper(_defaultSwappers[i], true);
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
        require(deployedPairsByName[IERC20Metadata(msg.sender).name()] == msg.sender, "!regPair");

        //ask minter to mint
        IMintable(token).mint(_receiver, _amount);
    }

    function burn(address _target, uint256 _amount) external{
        //ensure caller is a registered pair
        require(deployedPairsByName[IERC20Metadata(msg.sender).name()] == msg.sender, "!regPair");

        //ask minter to burn
        IMintable(token).mint(_target, _amount);
    }

    function claimFees(address _pair) external{
        IFraxlendPair(_pair).withdrawFees();
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
    error CircuitBreakerOnly();
    event WithdrawTo(address indexed user, uint256 amount);
}
