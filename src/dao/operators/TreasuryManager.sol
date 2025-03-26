// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ICore } from "src/interfaces/ICore.sol";
import { ITreasury } from "src/interfaces/ITreasury.sol";
import { CoreOwnable } from "src/dependencies/CoreOwnable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract TreasuryManager is CoreOwnable {
    using SafeERC20 for IERC20;

    address public constant prismaFeeReceiver = 0xfdCE0267803C6a0D209D3721d2f01Fd618e9CBF8;
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

    /**
        @notice Returns the active permissions granted to this contract
        @return retrieveToken Whether the guardian can retrieve tokens
        @return retrieveTokenExact Whether the guardian can retrieve tokens with an exact amount
        @return retrieveETH Whether the guardian can retrieve ETH
        @return retrieveETHExact Whether the guardian can retrieve ETH with an exact amount
        @return setTokenApproval Whether the guardian can set token approvals
        @return execute Whether the guardian can execute arbitrary calls
        @return safeExecute Whether the guardian can execute arbitrary calls with a return value
        @return transferTokenFromPrismaFeeReceiver Whether the guardian can transfer tokens from the prisma fee receiver
        @return approveTokenFromPrismaFeeReceiver Whether the guardian can approve tokens from the prisma fee receiver
    */
    function viewPermissions() external view returns (bool, bool, bool, bool, bool, bool, bool, bool, bool) {
        bool[] memory permissions = new bool[](9);
        (bool authorized,) = core.operatorPermissions(address(this), address(treasury), ITreasury.retrieveToken.selector);
        permissions[0] = authorized;
        (authorized,) = core.operatorPermissions(address(this), address(treasury), ITreasury.retrieveTokenExact.selector);
        permissions[1] = authorized;
        (authorized,) = core.operatorPermissions(address(this), address(treasury), ITreasury.retrieveETH.selector);
        permissions[2] = authorized;
        (authorized,) = core.operatorPermissions(address(this), address(treasury), ITreasury.retrieveETHExact.selector);
        permissions[3] = authorized;
        (authorized,) = core.operatorPermissions(address(this), address(treasury), ITreasury.setTokenApproval.selector);
        permissions[4] = authorized;
        (authorized,) = core.operatorPermissions(address(this), address(treasury), ITreasury.execute.selector);
        permissions[5] = authorized;
        (authorized,) = core.operatorPermissions(address(this), address(treasury), ITreasury.safeExecute.selector);
        permissions[6] = authorized;
        (authorized,) = core.operatorPermissions(address(this), address(prismaFeeReceiver), bytes4(keccak256("transferToken(address,address,uint256)")));
        permissions[7] = authorized;
        (authorized,) = core.operatorPermissions(address(this), address(prismaFeeReceiver), bytes4(keccak256("setTokenApproval(address,address,uint256)")));
        permissions[8] = authorized;
        return (permissions[0], permissions[1], permissions[2], permissions[3], permissions[4], permissions[5], permissions[6], permissions[7], permissions[8]);
    }
}
