// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ICore } from "src/interfaces/ICore.sol";
import { ITreasury } from "src/interfaces/ITreasury.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ISimpleReceiver } from "src/interfaces/ISimpleReceiver.sol";
import { IPrismaFeeReceiver } from "src/interfaces/prisma/IPrismaFeeReceiver.sol";
import { BaseUpgradeableOperator } from "src/dao/operators/BaseUpgradeableOperator.sol";

contract TreasuryManagerUpgradeable is BaseUpgradeableOperator {
    using SafeERC20 for IERC20;

    ICore public constant core = ICore(CORE);
    address public constant treasury = 0x4444444455bF42de586A88426E5412971eA48324;
    address public constant prismaFeeReceiver = 0xfdCE0267803C6a0D209D3721d2f01Fd618e9CBF8;

    address public manager;
    ISimpleReceiver public lpIncentivesReceiver;

    struct Permissions {
        bool retrieveToken;
        bool retrieveTokenExact;
        bool retrieveETH;
        bool retrieveETHExact;
        bool setTokenApproval;
        bool execute;
        bool safeExecute;
        bool transferTokenFromPrismaFeeReceiver;
        bool approveTokenFromPrismaFeeReceiver;
    }

    event ManagerSet(address indexed manager);

    modifier onlyManager() {
        require(msg.sender == manager, "!manager");
        _;
    }

    function initialize(address _manager) external initializer {
        manager = _manager;
        emit ManagerSet(manager);
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

    function transferTokenFromPrismaFeeReceiver(address token, address to, uint256 amount) external onlyManager {
        core.execute(
            prismaFeeReceiver,
            abi.encodeWithSelector(
                bytes4(keccak256("transferToken(address,address,uint256)")),
                token,
                to,
                amount
            )
        );
    }

    function approveTokenFromPrismaFeeReceiver(address token, address spender, uint256 amount) external onlyManager {
        core.execute(
            prismaFeeReceiver,
            abi.encodeWithSelector(
                bytes4(keccak256("setTokenApproval(address,address,uint256)")),
                token,
                spender,
                amount
            )
        );
    }

    function claimLpIncentives() external onlyManager returns (uint256) {
        return lpIncentivesReceiver.claimEmissions(manager);
    }

    function claimLpIncentivesTo(address _to) external onlyManager returns (uint256) {
        return lpIncentivesReceiver.claimEmissions(_to);
    }

    function recoverERC20(IERC20 token) external onlyManager {
        token.safeTransfer(manager, token.balanceOf(address(this)));
    }

    /**
     * @notice Sets the manager address that can execute treasury operations
     * @param _manager The address to set as the new manager
     */
    function setManager(address _manager) external onlyOwner {
        manager = _manager;
        emit ManagerSet(_manager);
    }
    
    function setLpIncentivesReceiver(address _lpIncentivesReceiver) external onlyManager {
        lpIncentivesReceiver = ISimpleReceiver(_lpIncentivesReceiver);
    }

    /**
        @notice Helper function to view the active permissions granted to this contract
        @return permissions The permissions struct
    */
    function viewPermissions() external view returns (Permissions memory permissions) {
        permissions.retrieveToken = hasPermission(address(treasury), ITreasury.retrieveToken.selector);
        permissions.retrieveTokenExact = hasPermission(address(treasury), ITreasury.retrieveTokenExact.selector);
        permissions.retrieveETH = hasPermission(address(treasury), ITreasury.retrieveETH.selector);
        permissions.retrieveETHExact = hasPermission(address(treasury), ITreasury.retrieveETHExact.selector);
        permissions.setTokenApproval = hasPermission(address(treasury), ITreasury.setTokenApproval.selector);
        permissions.execute = hasPermission(address(treasury), ITreasury.execute.selector);
        permissions.safeExecute = hasPermission(address(treasury), ITreasury.safeExecute.selector);
        permissions.transferTokenFromPrismaFeeReceiver = hasPermission(address(prismaFeeReceiver), IPrismaFeeReceiver.transferToken.selector);
        permissions.approveTokenFromPrismaFeeReceiver = hasPermission(address(prismaFeeReceiver), IPrismaFeeReceiver.setTokenApproval.selector);
    }

    function hasPermission(address target, bytes4 selector) public view returns (bool) {
        (bool authorized,) = core.operatorPermissions(address(this), target, selector);
        if (!authorized) (authorized,) = core.operatorPermissions(address(this), address(0), selector);
        return authorized;
    }
}
