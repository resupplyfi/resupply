import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockGovToken is ERC20 {
    constructor() ERC20("MockGovToken", "Mock") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}