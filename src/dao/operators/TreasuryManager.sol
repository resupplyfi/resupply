// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ICore } from "src/interfaces/ICore.sol";
import { ITreasury } from "src/interfaces/ITreasury.sol";
import { CoreOwnable } from "src/dependencies/CoreOwnable.sol";

contract TreasuryManager is CoreOwnable {
    address public immutable treasury;
    address public manager;

    event ManagerSet(address indexed manager);

    modifier onlyManager() {
        require(msg.sender == manager, "!manager");
        _;
    }

    constructor(address _core, address _treasury) CoreOwnable(_core) {
        treasury = _treasury;
    }

    function retrieveToken(address _token, address _to) external onlyManager {
        core.execute(
            treasury,
            abi.encodeWithSelector(
                ITreasury.retrieveToken.selector,
                _token,
                _to
            )
        );
    }

    function retrieveTokenExact(address _token, address _to, uint256 _amount) external onlyManager {
        core.execute(
            treasury,
            abi.encodeWithSelector(
                ITreasury.retrieveTokenExact.selector,
                _token,
                _to,
                _amount
            )
        );
    }

    function retrieveETH(address _to) external onlyManager {
        core.execute(
            treasury,
            abi.encodeWithSelector(
                ITreasury.retrieveETH.selector,
                _to
            )
        );
    }

    function retrieveETHExact(address _to, uint256 _amount) external onlyManager {
        core.execute(
            treasury,
            abi.encodeWithSelector(
                ITreasury.retrieveETHExact.selector,
                _to,
                _amount
            )
        );
    }

    function setTokenApproval(address _token, address _spender, uint256 _amount) external onlyManager {
        core.execute(
            treasury,
            abi.encodeWithSelector(
                ITreasury.setTokenApproval.selector,
                _token,
                _spender,
                _amount
            )
        );
    }

    /**
     * @notice Execute an arbitrary call to the treasury
     * @param _target The target address to call
     * @param _data The data to call the target with
     * @return success Whether the call was successful
     * @return result The result of the call as bytes
     * @dev Use `safeExecute` instead of this function if you need to ensure the call succeeds
     */
    function execute(address _target, bytes calldata _data) external onlyManager returns (bool, bytes memory result) {
        result = core.execute(
            treasury,
            abi.encodeWithSelector(
                ITreasury.execute.selector,
                _target,
                _data
            )
        );
        return abi.decode(result, (bool, bytes));
    }

    /**
     * @notice Safe execute an arbitrary call to the treasury
     * @param _target The target address to call
     * @param _data The data to call the target with
     * @return result The result of the call as bytes
     * @dev `safeExecute` enforces that the call must result in a success
     */
    function safeExecute(address _target, bytes calldata _data) external onlyManager returns (bytes memory result) {
        result = core.execute(
            treasury,
            abi.encodeWithSelector(
                ITreasury.safeExecute.selector,
                _target,
                _data
            )
        );
        return abi.decode(result, (bytes));
    }

    /**
     * @notice Sets the manager address that can execute treasury operations
     * @param _manager The address to set as the new manager
     */
    function setManager(address _manager) external onlyOwner {
        manager = _manager;
        emit ManagerSet(_manager);
    }
}
