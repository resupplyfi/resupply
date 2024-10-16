// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

// ====================================================================
// |     ______                   _______                             |
// |    / _____________ __  __   / ____(_____  ____ _____  ________   |
// |   / /_  / ___/ __ `| |/_/  / /_  / / __ \/ __ `/ __ \/ ___/ _ \  |
// |  / __/ / /  / /_/ _>  <   / __/ / / / / / /_/ / / / / /__/  __/  |
// | /_/   /_/   \__,_/_/|_|  /_/   /_/_/ /_/\__,_/_/ /_/\___/\___/   |
// |                                                                  |
// ====================================================================
// ==================== FraxlendPairAccessControl =====================
// ====================================================================
// Frax Finance: https://github.com/FraxFinance

// Primary Author
// Drake Evans: https://github.com/DrakeEvans

// Reviewers
// Dennis: https://github.com/denett

// ====================================================================

import "../../interfaces/IOwnership.sol";
import { FraxlendPairAccessControlErrors } from "./FraxlendPairAccessControlErrors.sol";

/// @title FraxlendPairAccessControl
/// @author Drake Evans (Frax Finance) https://github.com/drakeevans
/// @notice  An abstract contract which contains the access control logic for FraxlendPair
abstract contract FraxlendPairAccessControl is FraxlendPairAccessControlErrors {
    address public immutable registry;

    bool public isRepayPaused;
    bool public isRepayAccessControlRevoked;

    bool public isWithdrawPaused;
    bool public isWithdrawAccessControlRevoked;

    bool public isLiquidatePaused;
    bool public isLiquidateAccessControlRevoked;

    bool public isRedemptionPaused;

    bool public isInterestPaused;
    bool public isInterestAccessControlRevoked;

    /// @param _immutables abi.encode(address _circuitBreakerAddress, address _comptrollerAddress, address _timelockAddress)
    constructor(bytes memory _immutables) {
        // Handle Immutables Configuration
        (address _registry) = abi.decode(
            _immutables,
            (address)
        );
        registry = _registry;
    }

    // ============================================================================================
    // Functions: Access Control
    // ============================================================================================

    function _isProtocolOrOwner() internal view returns(bool){
        return msg.sender == registry || msg.sender == IOwnership(registry).owner();
    }

    function _requireProtocolOrOwner() internal view {
        if (
            !_isProtocolOrOwner()
        ) {
            revert OnlyProtocolOrOwner();
        }
    }

    /// @notice The ```RevokeRepayAccessControl``` event is emitted when repay access control is revoked
    event RevokeRepayAccessControl();

    function _revokeRepayAccessControl() internal {
        isRepayAccessControlRevoked = true;
        emit RevokeRepayAccessControl();
    }

    /// @notice The ```PauseRepay``` event is emitted when repay is paused or unpaused
    /// @param isPaused The new paused state
    event PauseRepay(bool isPaused);

    function _pauseRepay(bool _isPaused) internal {
        isRepayPaused = _isPaused;
        emit PauseRepay(_isPaused);
    }

    /// @notice The ```RevokeWithdrawAccessControl``` event is emitted when withdraw access control is revoked
    event RevokeWithdrawAccessControl();

    function _revokeWithdrawAccessControl() internal {
        isWithdrawAccessControlRevoked = true;
        emit RevokeWithdrawAccessControl();
    }

    /// @notice The ```PauseWithdraw``` event is emitted when withdraw is paused or unpaused
    /// @param isPaused The new paused state
    event PauseWithdraw(bool isPaused);

    function _pauseWithdraw(bool _isPaused) internal {
        isWithdrawPaused = _isPaused;
        emit PauseWithdraw(_isPaused);
    }

    /// @notice The ```RevokeLiquidateAccessControl``` event is emitted when liquidate access control is revoked
    event RevokeLiquidateAccessControl();

    function _revokeLiquidateAccessControl() internal {
        isLiquidateAccessControlRevoked = true;
        emit RevokeLiquidateAccessControl();
    }

    /// @notice The ```PauseLiquidate``` event is emitted when liquidate is paused or unpaused
    /// @param isPaused The new paused state
    event PauseLiquidate(bool isPaused);

    function _pauseLiquidate(bool _isPaused) internal {
        isLiquidatePaused = _isPaused;
        emit PauseLiquidate(_isPaused);
    }

    event PauseRedemption(bool isPaused);

    function _pauseRedemption(bool _isPaused) internal {
        isRedemptionPaused = _isPaused;
        emit PauseLiquidate(_isPaused);
    }

    /// @notice The ```RevokeInterestAccessControl``` event is emitted when interest access control is revoked
    event RevokeInterestAccessControl();

    function _revokeInterestAccessControl() internal {
        isInterestAccessControlRevoked = true;
        emit RevokeInterestAccessControl();
    }

    /// @notice The ```PauseInterest``` event is emitted when interest is paused or unpaused
    /// @param isPaused The new paused state
    event PauseInterest(bool isPaused);

    function _pauseInterest(bool _isPaused) internal {
        isInterestPaused = _isPaused;
        emit PauseInterest(_isPaused);
    }

}
