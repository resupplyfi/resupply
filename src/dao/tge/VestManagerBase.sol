// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { DelegatedOps } from '../../dependencies/DelegatedOps.sol';
import { CoreOwnable } from '../../dependencies/CoreOwnable.sol';

contract VestManagerBase is CoreOwnable, DelegatedOps {
    uint256 public immutable deadline;
    uint256 public immutable VEST_GLOBAL_START_TIME;
    
    uint256 public totalClaimed;
    IERC20 public token;

    mapping(address => Vest[]) public userVests;

    struct Vest {
        uint32 duration; // ~56k days
        uint112 amount;
        uint112 claimed;
    }

    event VestCreated(address indexed account, uint256 indexed duration, uint256 amount);
    event Claimed(address indexed account, uint256 amount);

    constructor(address _core, address _token, uint256 _timeUntilDeadline) CoreOwnable(_core) {
        token = IERC20(_token);
        deadline = block.timestamp + _timeUntilDeadline;
        VEST_GLOBAL_START_TIME = block.timestamp;
    }

    /// @notice Creates or adds to a vesting instance for an account
    /// @param _account The address to create the vest for
    /// @param _duration The duration of the vesting period in seconds
    /// @param _amount The amount of tokens to vest
    /// @return The total number of vesting instances for the account
    /// @dev Can only be called by the vest manager contract before the deadline
    function _createVest(
        address _account,
        uint32 _duration,
        uint112 _amount
    ) internal returns (uint256) {
        require(block.timestamp < deadline, "deadline passed");
        require(_account != address(0), "zero address");
        require(_amount > 0, "Amount must be greater than zero");

        uint256 length = numAccountVests(_account);

        // If the duration already exists, add to the total vest amount
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
            0 // claimed
        ));
        emit VestCreated(_account, _duration, _amount);
        return numAccountVests(_account);
    }

    function numAccountVests(address _account) public view returns (uint256) {
        return userVests[_account].length;
    }

    /**
     * @notice Claims all available vested tokens for an account
     * @param _account Address to claim tokens for
     * @return _claimed Total amount of tokens claimed
     * @dev Can be called by the account owner or a delegated caller
     */
    function claim(address _account) external callerOrDelegated(_account) returns (uint256 _claimed) {
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
    
        if (_claimed > 0) {
            totalClaimed += _claimed;
            token.transfer(_account, _claimed);
            emit Claimed(_account, _claimed);
        }
    }

    /**
     * @notice Get aggregated vesting data for an account. Includes all vests for the account.
     * @param _account Address of the account to query
     * @return _totalClaimable Amount of tokens that can be claimed by the account
     * @return _totalLocked Amount of tokens still locked in vesting
     * @return _totalClaimed Amount of tokens already claimed by the account
     * @return _totalVested Amount of tokens earned to date (including claimed)
     * @dev Iterates through all vests for the account to calculate totals
     */
    function getAggregatedAccountData(address _account) external view returns (
        uint256 _totalClaimable,
        uint256 _totalLocked,
        uint256 _totalClaimed,
        uint256 _totalVested
    ) {
        uint256 length = numAccountVests(_account);
        for (uint256 i = 0; i < length; i++) {
            (uint256 _claimable, uint256 _locked, uint256 _claimed, uint256 _vested) = _vestData(userVests[_account][i]);
            _totalClaimable += _claimable;
            _totalLocked += _locked;
            _totalClaimed += _claimed;
            _totalVested += _vested;
        }
    }

    /**
     * @notice Get single vest data for an account
     * @param _account Address of the account to query
     * @param index Index of the vest to query
     * @return _claimable Amount of tokens that can be claimed for the vest
     * @return _locked Amount of tokens still locked in the vest
     * @return _claimed Amount of tokens already claimed for the vest
     * @return _vested Amount of tokens earned to date (including claimed)
     */
    function getSingleVestData(address _account, uint256 index) external view returns (
        uint256 _claimable,
        uint256 _locked,
        uint256 _claimed,
        uint256 _vested
    ) {
        return _vestData(userVests[_account][index]);
    }

    function _vestData(Vest memory vest) internal view returns (
        uint256 _claimable,
        uint256 _locked,
        uint256 _claimed,
        uint256 _vested
    ){
        uint256 vested = _vestedAmount(vest);
        _claimable = vested - vest.claimed;
        _locked = vest.amount - vested;
        _claimed = vest.claimed;
        _vested = vested;
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
}
