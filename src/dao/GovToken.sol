import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { CoreOwnable } from "../../src/dependencies/CoreOwnable.sol";

contract GovToken is ERC20, CoreOwnable {
    uint256 public constant INITIAL_SUPPLY = 10_000_000e18;
    bool public minterFinalized;
    address public minter;

    event FinalizeMinter();
    event MinterSet(address indexed minter);

    modifier onlyMinter() {
        require(msg.sender == minter, "!minter");
        _;
    }

    constructor(
        address _core,
        address _vesting,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) CoreOwnable(_core) {
        _mint(_vesting, INITIAL_SUPPLY);
    }

    function mint(address _to, uint256 _amount) external onlyMinter {
        _mint(_to, _amount);
    }

    function setMinter(address _minter) external onlyOwner {
        require(!minterFinalized, "minter revoked");
        minter = _minter;
        emit MinterSet(_minter);
    }

    function finalizeMinter() external onlyOwner {
        require(!minterFinalized, "already finalized");
        minterFinalized = true;
        emit FinalizeMinter();
    }
}