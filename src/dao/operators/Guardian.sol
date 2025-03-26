import { ICore } from "src/interfaces/ICore.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { CoreOwnable } from "src/dependencies/CoreOwnable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Guardian is CoreOwnable {
    using SafeERC20 for IERC20;
    
    address public constant prismaFeeReceiver = 0xfdCE0267803C6a0D209D3721d2f01Fd618e9CBF8;
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

    function setGuardian(address _guardian) external onlyOwner {
        guardian = _guardian;
        emit GuardianSet(_guardian);
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

    function updateProposalDescription(uint256 proposalId, string calldata newDescription) external onlyGuardian {
        address voter = registry.getAddress("VOTER");
        core.execute(
            voter,
            abi.encodeWithSelector(IVoter.updateProposalDescription.selector, proposalId, newDescription)
        );
    }
    
    /**
        @notice Reverts the voter to the guardian address
        @dev This function serves as a safety measure until the DAO is fully operational and revokes its permissions.
     */
    function revertVoter() external onlyGuardian {
        (bool authorized,) = core.operatorPermissions(address(this), address(core), ICore.setVoter.selector);
        require(authorized, "Permission to revert voter not granted");
        core.execute(
            address(core),
            abi.encodeWithSelector(ICore.setVoter.selector, guardian)
        );
    }


    function setRegistryAddress(string memory _key, address _address) external onlyGuardian {
        core.execute(
            address(registry),
            abi.encodeWithSelector(
                IResupplyRegistry.setAddress.selector,
                _key,
                _address
            )
        );
    }

    function recoverERC20(IERC20 token) external onlyGuardian {
        token.safeTransfer(guardian, token.balanceOf(address(this)));
    }

    function _pausePair(address pair) internal {
        core.execute(
            pair, 
            abi.encodeWithSelector(IResupplyPair.pause.selector)
        );
        emit PairPaused(pair);
    }

    /**
        @notice Helper function to view the active permissions granted to this contract
        @return pausePair Whether the guardian can pause pairs
        @return cancelProposal Whether the guardian can cancel proposals
        @return updateProposalDescription Whether the guardian can update proposal descriptions
        @return revertVoter Whether the guardian can revert the voter
        @return setRegistryAddress Whether the guardian can set registry addresses
     */
    function viewPermissions() external view returns (bool, bool, bool, bool, bool) {
        address voter = registry.getAddress("VOTER");
        bool[] memory permissions = new bool[](5);
        (bool authorized,) = core.operatorPermissions(address(this), address(0), IResupplyPair.pause.selector);
        permissions[0] = authorized;
        (authorized,) = core.operatorPermissions(address(this), address(voter), IVoter.cancelProposal.selector);
        permissions[1] = authorized;
        (authorized,) = core.operatorPermissions(address(this), address(voter), IVoter.updateProposalDescription.selector);
        permissions[2] = authorized;
        (authorized,) = core.operatorPermissions(address(this), address(core), ICore.setVoter.selector);
        permissions[3] = authorized;
        (authorized,) = core.operatorPermissions(address(this), address(registry), IResupplyRegistry.setAddress.selector);
        permissions[4] = authorized;
        return (permissions[0], permissions[1], permissions[2], permissions[3], permissions[4]);
    }
}