import { CoreOwnable } from "../../src/dependencies/CoreOwnable.sol";

contract MockPair is CoreOwnable {
    uint256 public value;

    constructor(address _core) CoreOwnable(_core) {}

    function setValue(uint256 _value) external onlyOwner {
        value = _value;
    }
}