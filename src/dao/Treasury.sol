// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { CoreOwnable } from "../dependencies/CoreOwnable.sol";

contract Treasury is CoreOwnable {
    using SafeERC20 for IERC20;
    using Address for address;

    event RetrieveToken (address token,uint amount);
    event RetrieveETH (uint amount);

    receive() external payable {}

    constructor(address _core) CoreOwnable(_core) {}

    //Retrieve full balance of token in contract
    function retrieveToken(address _token, address _to) external onlyOwner {
        retrieveTokenExact(_token, _to, IERC20(_token).balanceOf(address(this)));
    }

    function retrieveTokenExact(address _token, address _to, uint _amount) public onlyOwner {
        IERC20(_token).safeTransfer(_to, _amount);
        emit RetrieveToken(_token, _amount);
    }

    function retrieveETH(address _to) external onlyOwner {
        retrieveETHExact(_to, address(this).balance);
    }

    function retrieveETHExact(address _to, uint _amount) public onlyOwner {
        (bool success, bytes memory returnData) = _to.call{value: _amount}("");
        require(success, "Sending ETH failed");
        emit RetrieveETH(_amount);
    }

    function setTokenApproval(address _token, address _spender, uint256 _amount) external onlyOwner {
        IERC20(_token).forceApprove(_spender, _amount);
    }

    function execute(address target, bytes calldata data) external returns (bool, bytes memory) {
        return _execute(target, data);
    }

    function safeExecute(address target, bytes calldata data) external returns (bytes memory) {
        (bool success, bytes memory result) = _execute(target, data);
        require(success, "CallFailed");
        return result;
    }

    function _execute(address target, bytes calldata data) internal onlyOwner returns (bool success, bytes memory result) {
        (success, result) = target.call(data);
    }
}