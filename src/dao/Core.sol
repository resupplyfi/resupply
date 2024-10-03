// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract Core {
    address public operator;

    event OperatorChanged(address indexed _address);

    constructor(address _operator) {
        operator = _operator;
        emit OperatorChanged(_operator);
    }

    function getName() external pure returns (string memory) {
        return "Core";
    }

    function setOperator(address _operator) external {
        require(msg.sender == operator, "!operator");

        operator = _operator;
        emit OperatorChanged(_operator);
    }

    function execute(
        address _to,
        uint256 _value,
        bytes calldata _data
    ) external returns (bool, bytes memory) {
        require(msg.sender == operator, "!auth");

        (bool success, bytes memory result) = _to.call{value: _value}(_data);

        return (success, result);
    }
}
