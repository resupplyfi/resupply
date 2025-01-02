import { CoreOwnable } from "../../src/dependencies/CoreOwnable.sol";

contract MockOperator is CoreOwnable {
    uint256 public value;
    uint256 public expectedValue;

    constructor(address _core) CoreOwnable(_core) {}

    function preHook(address caller, address target, bytes calldata data) external returns (bool) {
        return value <= expectedValue;
    }

    function postHook(bytes calldata result, address caller, address target, bytes calldata data) external returns (bool) {
        return value == expectedValue;
    }

    function setValue(uint256 _value) external onlyOwner {
        value = _value;
    }

    function setExpectedValue(uint256 _value) external {
        expectedValue = _value;
    }
}
