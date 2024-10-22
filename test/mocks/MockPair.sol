import { CorePausable } from "../../src/dependencies/CorePausable.sol";

contract MockPair is CorePausable {
    uint256 public value;

    constructor(address _core) CorePausable(_core) {}

    function setValue(uint256 _value) external onlyOwner {
        value = _value;
    }
}