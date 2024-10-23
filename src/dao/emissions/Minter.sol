import { CoreOwnable } from "../../dependencies/CoreOwnable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IGovToken } from "../../interfaces/IGovToken.sol";

contract Minter is CoreOwnable {
    IRSUP public token;

    constructor(address _core, IRSUP _token) CoreOwnable(_core) {
        token = _token;
    }

    function initialize(address _core, IGovToken _token) external initializer {
        __CoreOwnable_init(_core);
        token = _token;
    }

    function mint(address _to, uint256 _amount) external onlyOwner {
        _mint(_to, _amount);
    }
}
