import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { CoreOwnable } from "../../src/dependencies/CoreOwnable.sol";
import { IMinter } from "../../src/interfaces/IMinter.sol";

contract ResupplyToken is ERC20, CoreOwnable {
    IMinter public minter;
    bool public minterRevoked;

    event RevokeMinterRole();
    event MinterSet(IMinter indexed minter);

    modifier onlyMinter() {
        require(msg.sender == address(minter), "!minter");
        _;
    }

    constructor(address _core) ERC20("Resupply", "RSUP") CoreOwnable(_core) {}

    function mint(address _to, uint256 _amount) external onlyMinter {
        _mint(_to, _amount);
    }

    function setMinter(IMinter _minter) external onlyOwner {
        require(!minterRevoked, "minter revoked");
        minter = _minter;
        emit MinterSet(_minter);
    }

    function revokeMinter(IMinter _minter) external onlyOwner {
        minter = _minter;
        emit RevokeMinterRole();
    }
}