// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IGovStaker } from "../../interfaces/IGovStaker.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IResupplyRegistry } from "../../interfaces/IResupplyRegistry.sol";
import { IVestManager } from "../../interfaces/IVestManager.sol";

contract PermaStaker is Ownable2Step {

    address public immutable core;
    IResupplyRegistry public immutable registry;
    IVestManager public immutable vestManager;
    string public name;
    address public operator;
    IGovStaker public staker;
    
    event UnstakingAllowed(bool indexed allowed);
    event OperatorUpdated(address indexed operator);
    event StakerMigrated(address indexed oldStaker, address indexed newStaker);
    
    modifier onlyOwnerOrOperator {
        require(msg.sender == owner() || msg.sender == operator, "!ownerOrOperator");
        _;
    }

    constructor(
        address _core, 
        address _owner, 
        address _registry, 
        address _vestManager,
        string memory _name
    ) Ownable(_owner) {
        core = _core;
        name = _name;
        registry = IResupplyRegistry(_registry);
        IGovStaker _staker = _getStaker();
        require(address(_staker) != address(0), "Staker not set");
        _staker.irreversiblyCommitAccountAsPermanentStaker(address(this));
        staker = _staker;
        address token = _staker.stakeToken();
        vestManager = IVestManager(_vestManager);
        IERC20(token).approve(address(_staker), type(uint256).max);
    }

    function execute(address target, bytes calldata data) external returns (bool, bytes memory) {
        return _execute(target, data);
    }

    function safeExecute(address target, bytes calldata data) external returns (bytes memory) {
        (bool success, bytes memory result) = _execute(target, data);
        require(success, "CallFailed");
        return result;
    }

    function _execute(address target, bytes calldata data) internal onlyOwnerOrOperator returns (bool success, bytes memory result) {
        require(target != address(vestManager), "target not allowed");
        (success, result) = target.call(data);
    }

    function setOperator(address _operator) external onlyOwner {
        operator = _operator;
        emit OperatorUpdated(_operator);
    }

    function claimAndStake() external onlyOwnerOrOperator() returns(uint256 amount) {
        require(staker == _getStaker(), "Migration needed");
        amount = vestManager.claim(address(this));
        staker.stake(address(this), amount);
    }

    function migrateStaker() external onlyOwnerOrOperator {
        IGovStaker _oldStaker = staker;
        IGovStaker _newStaker = _getStaker();
        require(_oldStaker != _newStaker, "No migration needed");
        if (IERC20(address(_oldStaker)).balanceOf(address(this)) > 0) {
            _newStaker.setDelegateApproval(address(_oldStaker), true);
            _oldStaker.migrateStake();
        }
        staker = _newStaker;
    }
    
    function _getStaker() internal view returns (IGovStaker) {
        return IGovStaker(registry.staker());
    }
}