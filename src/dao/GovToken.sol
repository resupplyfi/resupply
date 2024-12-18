// import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import { CoreOwnable } from "../../src/dependencies/CoreOwnable.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { OFT } from "@layerzerolabs/oft-evm/contracts/OFT.sol";

contract GovToken is OFT {
    uint256 public immutable INITIAL_SUPPLY;
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
    ) OFT(_name, _symbol, address(0x1a44076050125825900e736c501f859c50fE728c), _core)
      Ownable(_core) {
        INITIAL_SUPPLY = _initialSupply;
        _mint(_vesting, _initialSupply);
    }

    function core() external returns(address){
        return owner();
    }

    function _transferOwnership(address newOwner) internal override {
        if(owner() == address(0)){
            super._transferOwnership(newOwner);
        }else{
            revert OwnableInvalidOwner(newOwner);
        }
    }

    function mint(address _to, uint256 _amount) external onlyMinter {
        _mint(_to, _amount);
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