pragma solidity ^0.8.22;

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
}