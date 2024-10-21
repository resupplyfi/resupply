import { CoreOwnable } from "../../dependencies/CoreOwnable.sol";
import { ICore } from "../../interfaces/ICore.sol";

contract GuardianOperator is CoreOwnable {

    address public guardian;

    event GuardianSet(address indexed guardian);

    modifier onlyGuardian() {
        require(msg.sender == guardian, "!guardian");
        _;
    }

    constructor(address _core, address _guardian) CoreOwnable(_core) {
        guardian = _guardian;
        emit GuardianSet(_guardian);
    }

    function setGuardian(address _guardian) public onlyOwner {
        guardian = _guardian;
        emit GuardianSet(_guardian);
    }

    function execute(address target, bytes calldata data) public onlyGuardian {
        core.execute(target, data);
    }

    // Helper function to interact with the core
    function pauseProtocol() public onlyGuardian {
        if (core.isProtocolPaused()) return;
        core.execute(
            address(core),
            abi.encodeWithSelector(
                bytes4(keccak256("pauseProtocol(bool)")),
                true
            )
        );
    }

    // Helper function to interact with the core
    function cancelProposal(uint256 id) public onlyGuardian {
        core.execute(
            core.voter(),
            abi.encodeWithSelector(
                bytes4(keccak256("cancelProposal(uint256)")),
                id
            )
        );
    }
}