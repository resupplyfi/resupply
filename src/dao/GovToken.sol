import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { CoreOwnable } from "../../src/dependencies/CoreOwnable.sol";
import { IMinter } from "../../src/interfaces/IMinter.sol";
import { IEmissionsController } from "../../src/interfaces/IEmissionsController.sol";

contract GovToken is ERC20, CoreOwnable {
    bool public controllerFinalized;
    address public emissionsController;

    event FinalizeEmissionsController();
    event EmissionsControllerSet(address indexed emissionsController);

    modifier onlyEmissionsController() {
        require(msg.sender == emissionsController, "!emissionsController");
        _;
    }

    constructor(address _core) ERC20("Resupply", "RSUP") CoreOwnable(_core) {}

    function mint(address _to, uint256 _amount) external onlyEmissionsController {
        _mint(_to, _amount);
    }

    function initialize(address _initVest, uint256 _initialSupply) external onlyOwner {
        require(emissionsController != address(0), "emissions controller not set");
        _mint(_initVest, _initialSupply);
        // TODO: airdrop + vest initial supply
    }

    function setEmissionsController(address _emissionsController) external onlyOwner {
        require(!controllerFinalized, "minter revoked");
        emissionsController = _emissionsController;
        emit EmissionsControllerSet(_emissionsController);
    }

    function finalizeEmissionsController() external onlyOwner {
        require(!controllerFinalized, "already finalized");
        controllerFinalized = true;
        emit FinalizeEmissionsController();
    }
}