import { ICore } from "src/interfaces/ICore.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { CoreOwnable } from "src/dependencies/CoreOwnable.sol";

contract Guardian is CoreOwnable {
    IResupplyRegistry public immutable registry;
    address public guardian;

    modifier onlyGuardian() {
        require(msg.sender == guardian, "!guardian");
        _;
    }

    event GuardianSet(address indexed newGuardian);
    event PairPaused(address indexed pair);

    constructor(address _core, address _registry) CoreOwnable(_core) {
        registry = IResupplyRegistry(_registry);
    }

    function pauseAllPairs() external onlyGuardian {
        address[] memory pairs = registry.getAllPairAddresses();
        for (uint256 i = 0; i < pairs.length; i++) {
            _pausePair(pairs[i]);
        }
    }

    function pausePair(address pair) external onlyGuardian {
        _pausePair(pair);
    }

    function cancelProposal(uint256 proposalId) external onlyGuardian {
        address voter = registry.getAddress("VOTER");
        core.execute(
            voter, 
            abi.encodeWithSelector(IVoter.cancelProposal.selector, proposalId)
        );
    }

    function setGuardian(address _guardian) external onlyOwner {
        guardian = _guardian;
        emit GuardianSet(_guardian);
    }

    function _pausePair(address pair) internal {
        core.execute(
            pair, 
            abi.encodeWithSelector(IResupplyPair.pause.selector)
        );
        emit PairPaused(pair);
    }
}
