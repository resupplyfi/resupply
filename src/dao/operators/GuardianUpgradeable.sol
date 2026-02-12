// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ICore } from "src/interfaces/ICore.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { BaseUpgradeableOperator } from "src/dao/operators/BaseUpgradeableOperator.sol";
import { ISwapperOdos } from "src/interfaces/ISwapperOdos.sol";
import { IInsurancePool } from "src/interfaces/IInsurancePool.sol";
import { IBorrowLimitController } from "src/interfaces/IBorrowLimitController.sol";
import { IRedemptionHandler } from "src/interfaces/IRedemptionHandler.sol";

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
        bool setRegistryAddress;
        bool revokeSwapperApprovals;
        bool pauseIPWithdrawals;
        bool cancelRamp;
        bool updateRedemptionGuardSettings;
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

    /**
        @notice Pause IP Withdrawals by setting the withdraw window to 0
     */
    function pauseIPWithdrawals() external onlyGuardian {
        address insurancePool = registry.getAddress("INSURANCE_POOL");
        uint256 withdrawTime = IInsurancePool(insurancePool).withdrawTime();
        core.execute(
            address(insurancePool),
            abi.encodeWithSelector(IInsurancePool.setWithdrawTimers.selector, withdrawTime, 0)
        );
    }

    /**
        @notice Cancel borrow limit ramp for a pair on BorrowLimitController
        @param _pair The pair to cancel the ramp for
     */
    function cancelRamp(address _pair) external onlyGuardian {
        address borrowLimitController = registry.getAddress("BORROW_LIMIT_CONTROLLER");
        core.execute(
            address(borrowLimitController),
            abi.encodeWithSelector(IBorrowLimitController.cancelRamp.selector, _pair)
        );
    }

    function updateRedemptionGuardSettings(bool guardEnabled, uint256 priceThreshold) external onlyGuardian {
        address handler = _getRedemptionHandler();
        core.execute(
            handler,
            abi.encodeWithSelector(IRedemptionHandler.updateGuardSettings.selector, guardEnabled, priceThreshold)
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
        address insurancePool = registry.getAddress("INSURANCE_POOL");
        address voter = _getVoter();
        address redemptionHandler = _getRedemptionHandler();
        permissions.pauseAllPairs = hasPermission(address(0), IResupplyPair.pause.selector);
        permissions.cancelProposal = hasPermission(voter, IVoter.cancelProposal.selector);
        permissions.updateProposalDescription = hasPermission(voter, IVoter.updateProposalDescription.selector);
        permissions.setRegistryAddress = hasPermission(address(registry), IResupplyRegistry.setAddress.selector);
        permissions.revokeSwapperApprovals = hasPermission(swapper, ISwapperOdos.revokeApprovals.selector);
        permissions.pauseIPWithdrawals = hasPermission(insurancePool, IInsurancePool.setWithdrawTimers.selector);
        permissions.cancelRamp = hasPermission(address(0), IBorrowLimitController.cancelRamp.selector);
        permissions.updateRedemptionGuardSettings =
            hasPermission(redemptionHandler, IRedemptionHandler.updateGuardSettings.selector);
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

    function _getRedemptionHandler() internal view returns (address) {
        return registry.getAddress("REDEMPTION_HANDLER");
    }

}
