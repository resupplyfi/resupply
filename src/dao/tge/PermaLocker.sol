// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IGovStaker } from "../../interfaces/IGovStaker.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPairRegistry } from "../../interfaces/IPairRegistry.sol";

contract PermaLocker is Ownable2Step {

    address public immutable core;
    IPairRegistry public immutable registry;
    bool public unstakingAllowed;
    string public name;
    IGovStaker public staker;
    IGovStaker public oldStaker;
    IERC20 public govToken;
    address public operator;
    

    event UnstakingAllowed(bool indexed allowed);
    event OperatorUpdated(address indexed operator);
    event StakerMigrated(address indexed oldStaker, address indexed newStaker);
    
    modifier onlyOwnerOrOperator {
        require(msg.sender == owner() || msg.sender == operator, "!ownerOrOperator");
        _;
    }

    modifier noUnstaking {
        bool shouldCheck = !unstakingAllowed;
        uint256 pre;
        if (shouldCheck) {
            pre = staker.balanceOf(address(this));
        }
        _;
        if (shouldCheck) {
            require(
                staker.balanceOf(address(this)) >= pre, 
                "UnstakingForbidden"
            );
        }
    }

    constructor(address _core, address _owner, address _staker, address _registry, string memory _name) {
        core = _core;
        registry = IPairRegistry(_registry);
        staker = IGovStaker(_staker);
        govToken = IERC20(IGovStaker(_staker).stakeToken());
        govToken.approve(address(staker), type(uint256).max);
        registry = IPairRegistry(_registry);
        name = _name;
        _transferOwnership(_owner);
    }

    function execute(address target, bytes calldata data) external returns (bool, bytes memory) {
        return _execute(target, data);
    }

    function safeExecute(address target, bytes calldata data) external returns (bytes memory) {
        (bool success, bytes memory result) = _execute(target, data);
        require(success, "CallFailed");
        return result;
    }

    function _execute(address target, bytes calldata data) internal onlyOwnerOrOperator noUnstaking returns (bool success, bytes memory result) {
        require(target != address(0), "Invalid target address");
        (success, result) = target.call(data);
    }

    function allowUnstaking(bool _allowed) external {
        require(msg.sender == core, "!core");
        unstakingAllowed = _allowed;
        emit UnstakingAllowed(_allowed);
    }

    function stake(address account, uint256 amount) external onlyOwnerOrOperator {
        staker.stake(account, amount);
    }

    function stake() external onlyOwnerOrOperator {
        staker.stake(address(this), govToken.balanceOf(address(this)));
    }

    function setOperator(address _operator) external onlyOwner {
        operator = _operator;
        emit OperatorUpdated(_operator);
    }

    /// @notice Migrates the staker contract to a new address
    /// @dev Uses registry value to set new staker
    function migrateStaker() external onlyOwner {
        address _newStaker = registry.staker();
        require(_newStaker != address(0), "Staker not set");
        address _oldStaker = address(staker);
        require(_oldStaker != _newStaker, "No change");

        govToken.approve(_newStaker, type(uint256).max);
        govToken.approve(_oldStaker, 0);
        staker = IGovStaker(_newStaker);

        emit StakerMigrated(_oldStaker, _newStaker);
    }
}
