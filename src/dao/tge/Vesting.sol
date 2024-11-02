// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { DelegatedOps } from '../../dependencies/DelegatedOps.sol';
import { CoreOwnable } from '../../dependencies/CoreOwnable.sol';

contract Vesting is CoreOwnable, DelegatedOps {
    IERC20 public token;
    address public claimerContract;
    uint256 totalClaimed;
    uint256 totalAllocated;
    uint256 public immutable deadline;
    mapping(address => Vest[]) public userVests;

    struct Vest {
        uint256 start;
        uint256 duration;
        uint256 amount;
        uint256 claimed;
    }

    event Claimed(address indexed account, uint256 amount);

    constructor(address _core, IERC20 _token, uint256 _timeUntilDeadline) CoreOwnable(_core) {
        token = _token;
        deadline = block.timestamp + _timeUntilDeadline;
    }

    modifier onlyClaimer() {
        require(msg.sender == claimerContract, "!claimer");
        _;
    }

    function createVest(
        address _account,
        uint256 _start,
        uint256 _duration,
        uint256 _amount
    ) external onlyClaimer returns (uint256) {
        require(block.timestamp < deadline, "deadline passed");
        require(_account != address(0), "zero address");
        require(_amount > 0, "Amount must be greater than zero");

        userVests[_account].push(Vest(
            _start,
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
            uint256 claimable = _claimableAmount(vests[i]);
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
     * @return totalClaimable Amount of tokens that can be claimed by the account
     * @return totalLocked Amount of tokens still locked in vesting
     * @return totalClaimed Amount of tokens already claimed by the account
     * @return totalVested Amount of tokens earned to date (including claimed)
     * @dev Iterates through all vests for the account to calculate totals
     */
    function getAggregatedAccountData(address _account) external view returns (
        uint256 totalClaimable,
        uint256 totalLocked,
        uint256 totalClaimed,
        uint256 totalVested
    ) {
        uint256 length = numAccountVests(_account);
        for (uint256 i = 0; i < length; i++) {
            (uint256 _totalClaimable, uint256 _totalLocked, uint256 _totalClaimed, uint256 _totalVested) = _vestData(userVests[_account][i]);
            totalClaimable += _totalClaimable;
            totalLocked += _totalLocked;
            totalClaimed += _totalClaimed;
            totalVested += _totalVested;
        }
    }

    /**
     * @notice Get single vest data for an account
     * @param _account Address of the account to query
     * @param index Index of the vest to query
     * @return totalClaimable Amount of tokens that can be claimed for the vest
     * @return totalLocked Amount of tokens still locked in the vest
     * @return totalClaimed Amount of tokens already claimed for the vest
     * @return totalVested Amount of tokens earned to date (including claimed)
     */
    function getSingleVestData(address _account, uint256 index) external view returns (
        uint256 totalClaimable,
        uint256 totalLocked,
        uint256 totalClaimed,
        uint256 totalVested
    ) {
        return _vestData(userVests[_account][index]);
    }

    function _vestData(Vest memory vest) internal view returns (
        uint256 totalClaimable,
        uint256 totalLocked,
        uint256 totalClaimed,
        uint256 totalVested
    ){
        uint256 vested = _vestedAmount(vest);
        totalClaimable = vested - vest.claimed;
        totalLocked = vest.amount - vested;
        totalClaimed = vest.claimed;
        totalVested = vested;
    }

    function _claimableAmount(Vest storage vest) internal view returns (uint256) {
        return _vestedAmount(vest) - vest.claimed;
    }

    function _vestedAmount(Vest memory vest) internal view returns (uint256) {
        if (block.timestamp < vest.start) {
            return 0;
        } else if (block.timestamp >= vest.start + vest.duration) {
            return vest.amount;
        } else {
            return (vest.amount * (block.timestamp - vest.start)) / vest.duration;
        }
    }

    function sweepUnclaimed() external onlyOwner {
        require(block.timestamp >= deadline, "!deadline");
        token.transfer(address(core), getUnallocatedBalance());
    }

    function getUnallocatedBalance() public view returns (uint256) {
        return token.balanceOf(address(this)) - totalAllocated;
    }

    function setClaimer(address _claimer) external onlyOwner {
        require(claimerContract == address(0), "Already set");
        require(_claimer != address(0), "Zero address");
        claimerContract = _claimer;
    }
}
