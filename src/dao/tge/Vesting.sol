// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { DelegatedOps } from '../../dependencies/DelegatedOps.sol';
import { CoreOwnable } from '../../dependencies/CoreOwnable.sol';

contract Vesting is CoreOwnable, DelegatedOps {
    uint256 public immutable deadline;
    uint256 public immutable VEST_GLOBAL_START_TIME;
    
    address public vestManagerContract;
    uint256 public totalClaimed;
    uint256 public totalAllocated;
    IERC20 public token;
    mapping(address => Vest[]) public userVests;

    struct Vest {
        uint32 duration; // ~56k days
        uint112 amount;
        uint112 claimed;
    }

    event Claimed(address indexed account, uint256 amount);

    constructor(address _core, IERC20 _token, uint256 _timeUntilDeadline) CoreOwnable(_core) {
        token = _token;
        deadline = block.timestamp + _timeUntilDeadline;
        VEST_GLOBAL_START_TIME = block.timestamp;
    }

    modifier onlyVestManager() {
        require(msg.sender == vestManagerContract, "!vestManager");
        _;
    }

    function createVest(
        address _account,
        uint32 _duration,
        uint112 _amount
    ) external onlyVestManager returns (uint256) {
        require(block.timestamp < deadline, "deadline passed");
        require(_account != address(0), "zero address");
        require(_amount > 0, "Amount must be greater than zero");

        userVests[_account].push(Vest(
            _duration,
            _amount,
            0 // claimed
        ));

        totalAllocated += _amount;

        return numAccountVests(_account);
    }

    function numAccountVests(address _account) public view returns (uint256) {
        return userVests[_account].length;
    }

    function claim(address _account) callerOrDelegated(_account) public {
        _claim(_account, 0, userVests[_account].length);
    }

    function claimWithBounds(address _account, uint256 start, uint256 stop) callerOrDelegated(_account) public {
        require(start < stop && stop <= userVests[_account].length, "Invalid start or stop index");
        _claim(_account, start, stop);
    }

    function _claim(address _account, uint256 start, uint256 stop) internal returns (uint256 _totalClaimable) {
        Vest[] storage vests = userVests[_account];
        require(vests.length > 0, "No vests to claim");

        for (uint256 i = start; i < stop; i++) {
            uint112 claimable = _claimableAmount(vests[i]);
            if (claimable > 0) {
                vests[i].claimed += claimable;
                _totalClaimable += claimable;
            }
        }
    
        if (_totalClaimable > 0) {
            token.transfer(_account, _totalClaimable);
            totalClaimed += _totalClaimable;
            emit Claimed(_account, _totalClaimable);
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

    function sweepUnclaimed() external onlyOwner {
        require(block.timestamp >= deadline, "!deadline");
        token.transfer(address(core), getUnallocatedBalance());
    }

    function getUnallocatedBalance() public view returns (uint256) {
        return token.balanceOf(address(this)) - totalAllocated;
    }

    function setVestManager(address _vestManager) external onlyOwner {
        require(vestManagerContract == address(0), "Already set");
        require(_vestManager != address(0), "Zero address");
        vestManagerContract = _vestManager;
    }
}
