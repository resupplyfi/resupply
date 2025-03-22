// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ICore } from "src/interfaces/ICore.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { CoreOwnable } from "src/dependencies/CoreOwnable.sol";

contract TreasuryManager is CoreOwnable {
    IResupplyRegistry public immutable registry;
    address public immutable treasury;
    address public manager;

    event ManagerSet(address indexed manager);

    modifier onlyManager() {
        require(msg.sender == manager, "!manager");
        _;
    }

    constructor(address _core, address _registry) CoreOwnable(_core) {
        registry = IResupplyRegistry(_registry);
        treasury = registry.treasury();
    }

    function retrieveToken(address _token, address _to) external onlyManager {
        core.execute(
            treasury,
            abi.encodeWithSelector(
                bytes4(keccak256("retrieveToken(address,address)")),
                _token,
                _to
            )
        );
    }

    function retrieveTokenExact(address _token, address _to, uint256 _amount) external onlyManager {
        core.execute(
            treasury,
            abi.encodeWithSelector(
                bytes4(keccak256("retrieveTokenExact(address,address,uint256)")),
                _token,
                _to,
                _amount
            )
        );
    }

    function retrieveETH(address _to) external onlyManager {
        address treasury = registry.treasury();
        core.execute(
            treasury,
            abi.encodeWithSelector(
                bytes4(keccak256("retrieveETH(address)")),
                _to
            )
        );
    }

    function retrieveETHExact(address _to, uint256 _amount) external onlyManager {
        address treasury = registry.treasury();
        core.execute(
            treasury,
            abi.encodeWithSelector(
                bytes4(keccak256("retrieveETHExact(address,uint256)")),
                _to,
                _amount
            )
        );
    }

    function setTokenApproval(address _token, address _spender, uint256 _amount) external onlyManager {
        address treasury = registry.treasury();
        core.execute(
            treasury,
            abi.encodeWithSelector(
                bytes4(keccak256("setTokenApproval(address,address,uint256)")),
                _token,
                _spender,
                _amount
            )
        );
    }

    function execute(address _target, bytes calldata _data) external onlyManager returns (bool success, bytes memory result) {
        address treasury = registry.treasury();
        result = core.execute(
            treasury,
            abi.encodeWithSelector(
                bytes4(keccak256("execute(address,bytes)")),
                _target,
                _data
            )
        );
        (success, result) = abi.decode(result, (bool, bytes));
        return (success, result);
    }

    function safeExecute(address _target, bytes calldata _data) external onlyManager returns (bytes memory result) {
        address treasury = registry.treasury();
        result = core.execute(
            treasury,
            abi.encodeWithSelector(
                bytes4(keccak256("safeExecute(address,bytes)")),
                _target,
                _data
            )
        );
        bool success;
        (success, result) = abi.decode(result, (bool, bytes));
        require(success, "TreasuryManager: Safe execution failed");
        return result;
    }

    function setManager(address _manager) external onlyOwner {
        manager = _manager;
        emit ManagerSet(_manager);
    }
}
