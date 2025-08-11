import { ICore } from "src/interfaces/ICore.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { CoreOwnable } from "src/dependencies/CoreOwnable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { BaseUpgradeableOperator } from "src/dao/operators/BaseUpgradeableOperator.sol";
import { ISwapperOdos } from "src/interfaces/ISwapperOdos.sol";

contract GuardianUpgradeable is BaseUpgradeableOperator {
    using SafeERC20 for IERC20;

    ICore public constant core = ICore(CORE);
    IResupplyRegistry public constant registry = IResupplyRegistry(0x10101010E0C3171D894B71B3400668aF311e7D94);
    address public guardian;
    mapping(string => bool) public guardedRegistryKeys;

    struct Permissions {
        bool pauseAllPairs;
        bool cancelProposal;
        bool updateProposalDescription;
        bool revertVoter;
        bool setRegistryAddress;
        bool revokeSwapperApprovals;
    }

    event GuardianSet(address indexed newGuardian);
    event PairPaused(address indexed pair);
    event GuardedRegistryKeySet(string key, bool indexed guarded);

    modifier onlyGuardian() {
        require(msg.sender == guardian, "!guardian");
        _;
    }

    function initialize(address _guardian) external initializer {
        guardian = _guardian;
        emit GuardianSet(_guardian);
    }

    function setGuardian(address _guardian) external onlyOwner {
        guardian = _guardian;
        emit GuardianSet(_guardian);
    }

    function setGuardedRegistryKey(string memory _key, bool _guarded) external onlyOwner {
        guardedRegistryKeys[_key] = _guarded;
        emit GuardedRegistryKeySet(_key, _guarded);
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
        address voter = _getVoter();
        core.execute(
            voter, 
            abi.encodeWithSelector(IVoter.cancelProposal.selector, proposalId)
        );
    }

    function updateProposalDescription(uint256 proposalId, string calldata newDescription) external onlyGuardian {
        address voter = _getVoter();
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
        require(!guardedRegistryKeys[_key], "Key is guarded");
        core.execute(
            address(registry),
            abi.encodeWithSelector(
                IResupplyRegistry.setAddress.selector,
                _key,
                _address
            )
        );
    }

    function revokeSwapperApprovals() external onlyGuardian {
        address swapper = registry.getAddress("SWAPPER_ODOS");
        core.execute(
            address(swapper),
            abi.encodeWithSelector(ISwapperOdos.revokeApprovals.selector)
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
        @return permissions struct with the active permissions
     */
    function viewPermissions() external view returns (Permissions memory permissions) {
        address swapper = registry.getAddress("SWAPPER_ODOS");
        address voter = _getVoter();
        permissions.pauseAllPairs = hasPermission(address(0), IResupplyPair.pause.selector);
        permissions.cancelProposal = hasPermission(address(voter), IVoter.cancelProposal.selector);
        permissions.updateProposalDescription = hasPermission(address(voter), IVoter.updateProposalDescription.selector);
        permissions.revertVoter = hasPermission(address(core), ICore.setVoter.selector);
        permissions.setRegistryAddress = hasPermission(address(registry), IResupplyRegistry.setAddress.selector);
        permissions.revokeSwapperApprovals = hasPermission(address(swapper), ISwapperOdos.revokeApprovals.selector);
        return permissions;
    }

    function hasPermission(address target, bytes4 selector) public view returns (bool authorized) {
        (authorized,) = core.operatorPermissions(address(this), address(0), selector);
        if (authorized) return true;
        (authorized,) = core.operatorPermissions(address(this), target, selector);
        return authorized;
    }

    function _getVoter() internal view returns (address) {
        return registry.getAddress("VOTER");
    }
}