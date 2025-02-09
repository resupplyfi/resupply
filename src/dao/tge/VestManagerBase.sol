// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { DelegatedOps } from '../../dependencies/DelegatedOps.sol';
import { CoreOwnable } from '../../dependencies/CoreOwnable.sol';
import { IVestClaimCallback } from 'src/interfaces/IVestClaimCallback.sol';

contract VestManagerBase is CoreOwnable, DelegatedOps {
    uint256 public immutable VEST_GLOBAL_START_TIME;
    IERC20 public token;

    mapping(address => Vest[]) public userVests;
    mapping(address => ClaimSettings) public claimSettings;

    struct Vest {
        uint32 duration; // max of ~56k days
        uint112 amount;
        uint112 claimed;
    }

    struct ClaimSettings {
        bool allowPermissionlessClaims;
        address recipient;
    }

    event VestCreated(address indexed account, uint256 indexed duration, uint256 amount);
    event Claimed(address indexed account, uint256 amount);
    event ClaimSettingsSet(address indexed account, bool indexed allowPermissionlessClaims, address indexed recipient);

    constructor(address _core, address _token) CoreOwnable(_core) {
        token = IERC20(_token);
        VEST_GLOBAL_START_TIME = block.timestamp;
    }

    /// @notice Creates or adds to a vesting instance for an account
    /// @param _account The address to create the vest for
    /// @param _duration The duration of the vesting period in seconds
    /// @param _amount The amount of tokens to vest
    /// @return The total number of vesting instances for the account
    function _createVest(
        address _account,
        uint32 _duration,
        uint112 _amount
    ) internal returns (uint256) {
        require(_account != address(0), "zero address");
        require(_amount > 0, "Amount must be greater than zero");

        uint256 length = numAccountVests(_account);

        // If a vest with matching duration already exists, simply add to its amount
        for (uint256 i = 0; i < length; i++) {
            if (userVests[_account][i].duration == _duration) {
                userVests[_account][i].amount += _amount;
                return length;
            }
        }

        // If the duration does not exist, create a new vest
        userVests[_account].push(Vest(
            _duration,
            _amount,
            0
        ));

        emit VestCreated(_account, _duration, _amount);
        return length + 1;
    }

    function numAccountVests(address _account) public view returns (uint256) {
        return userVests[_account].length;
    }

    /**
     * @notice Claims all available vested tokens for an account
     * @param _account Address to claim tokens for
     * @return _claimed Total amount of tokens claimed
     * @dev Any caller can claim on behalf of an account, unless explicitly blocked via account's claimSettings
     */
    function claim(address _account) external returns (uint256 _claimed) {
        address recipient = _enforceClaimSettings(_account);
        _claimed = _claim(_account);
        if (_claimed > 0) {
            token.transfer(recipient, _claimed);
            emit Claimed(_account, _claimed);
        }
    }

    /**
     * @notice Claims all available vested tokens for an account, and calls a callback to handle the tokens
     * @dev Important: the claimed tokens are transferred to the callback contract for handling, not the recipient
     * @param _account Address to claim tokens for
     * @param _callback Address of the callback contract to use
     * @return _claimed Total amount of tokens claimed
     */
    function claimWithCallback(
        address _account, 
        address _callback
    ) external callerOrDelegated(_account) returns (uint256 _claimed) {
        address recipient = _enforceClaimSettings(_account);
        _claimed = _claim(_account);
        if (_claimed > 0) {
            token.transfer(_callback, _claimed);
            require(IVestClaimCallback(_callback).onClaim(_account, recipient, _claimed), "callback failed");
            emit Claimed(_account, _claimed);
        }
    }

    function _claim(address _account) internal returns (uint256 _claimed) {
        Vest[] storage vests = userVests[_account];
        uint256 length = vests.length;
        require(length > 0, "No vests to claim");

        for (uint256 i = 0; i < length; i++) {
            uint112 claimable = _claimableAmount(vests[i]);
            if (claimable > 0) {
                vests[i].claimed += claimable;
                _claimed += claimable;
            }
        }
    }



    function _enforceClaimSettings(address _account) internal view returns (address) {
        ClaimSettings memory settings = claimSettings[_account];
        if (!settings.allowPermissionlessClaims) {
            require(msg.sender == _account, "!authorized");
        }
        return settings.recipient != address(0) ? settings.recipient : _account;
    }

    /**
     * @notice Get aggregated vesting data for an account. Includes all vests for the account.
     * @param _account Address of the account to query
     * @return _totalAmount Total amount of tokens in all vests for the account
     * @return _totalClaimable Amount of tokens that can be claimed by the account
     * @return _totalClaimed Amount of tokens already claimed by the account
     * @dev Iterates through all vests for the account to calculate totals
     */
    function getAggregateVestData(address _account) external view returns (
        uint256 _totalAmount,
        uint256 _totalClaimable,
        uint256 _totalClaimed
    ) {
        uint256 length = numAccountVests(_account);
        for (uint256 i = 0; i < length; i++) {
            (uint256 _total, uint256 _claimable, uint256 _claimed,) = _vestData(userVests[_account][i]);
            _totalAmount += _total;
            _totalClaimable += _claimable;
            _totalClaimed += _claimed;
        }
    }

    /**
     * @notice Get single vest data for an account
     * @param _account Address of the account to query
     * @param index Index of the vest to query
     * @return _total Total amount of tokens in the vest
     * @return _claimable Amount of tokens that can be claimed for the vest
     * @return _claimed Amount of tokens already claimed for the vest
     * @return _timeRemaining Time remaining until vesting is complete
     */
    function getSingleVestData(address _account, uint256 index) external view returns (
        uint256 _total,
        uint256 _claimable,
        uint256 _claimed,
        uint256 _timeRemaining
    ) {
        return _vestData(userVests[_account][index]);
    }

    function _vestData(Vest memory vest) internal view returns (
        uint256 _total,
        uint256 _claimable,
        uint256 _claimed,
        uint256 _timeRemaining
    ){
        uint256 vested = _vestedAmount(vest);
        _total = vest.amount;
        _claimable = vested - vest.claimed;
        _claimed = vest.claimed;
        _timeRemaining = vest.duration - (block.timestamp - VEST_GLOBAL_START_TIME);
    }

    function _claimableAmount(Vest storage vest) internal view returns (uint112) {
        return uint112(_vestedAmount(vest) - vest.claimed);
    }

    function _vestedAmount(Vest memory vest) internal view returns (uint256) {
        if (block.timestamp < VEST_GLOBAL_START_TIME) {
            return 0;
        } else if (block.timestamp >= VEST_GLOBAL_START_TIME + vest.duration) {
            return vest.amount;
        } else {
            return (vest.amount * (block.timestamp - VEST_GLOBAL_START_TIME)) / vest.duration;
        }
    }

    function setClaimSettings( 
        bool _allowPermissionlessClaims, 
        address _recipient
    ) external {
        claimSettings[msg.sender] = ClaimSettings(_allowPermissionlessClaims, _recipient);
        emit ClaimSettingsSet(msg.sender, _allowPermissionlessClaims, _recipient);
    }
}