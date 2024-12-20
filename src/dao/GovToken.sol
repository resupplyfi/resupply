import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { CoreOwnable } from "../../src/dependencies/CoreOwnable.sol";

contract GovToken is ERC20, CoreOwnable {
    uint256 public immutable INITIAL_SUPPLY;
    uint256 public globalSupply;
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
        uint256 _initialSupply,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) CoreOwnable(_core) {
        INITIAL_SUPPLY = _initialSupply;
        _mint(_vesting, _initialSupply);
        globalSupply += _initialSupply;
    }

    function mint(address _to, uint256 _amount) external onlyMinter {
        _mint(_to, _amount);
        globalSupply += _amount;
    }

    function setMinter(address _minter) external onlyOwner {
        require(!minterFinalized, "minter finalized");
        minter = _minter;
        emit MinterSet(_minter);
    }

    function finalizeMinter() external onlyOwner {
        require(!minterFinalized, "minter finalized");
        minterFinalized = true;
        emit FinalizeMinter();
    }
}