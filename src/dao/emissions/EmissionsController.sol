// SPDX-License-Identifier: MIT

pragma solidity ^0.8.22;

import { CoreOwnable } from "../../dependencies/CoreOwnable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { EpochTracker } from "../../dependencies/EpochTracker.sol";
import { IMinter } from "../../interfaces/IMinter.sol";

contract EmissionsController is CoreOwnable, EpochTracker {

    IERC20 immutable public govToken;
    uint256 public emissionsRate;
    uint256 public constant PRECISION = 1e18;
    uint256[] private emissionsSchedule;
    uint256 public lastEpochTransition;
    uint256 public epochsPer;
    uint256 public tailRate;
    uint256 public lastEmissionsMint;
    uint256 public unallocated;
    uint256 public lastUpdateEpoch;
    uint256 constant YEAR = 31557600;

    constructor(address _core, IERC20 _govToken, uint256[] memory _emissionsSchedule, uint256 _epochsPer) CoreOwnable(_core) EpochTracker(_core) {
        govToken = _govToken;
        emissionsSchedule = _emissionsSchedule;
        epochsPer = _epochsPer;lastEmissionsMint = startTime;
        tailRate = 1e16; // 2%
        lastEmissionsMint = startTime;
    }


    function setEmissionsSplits(address _minter, uint256 _amount) external onlyOwner {
        
        
    }

    function mintEmissions() external {
        uint256 epoch = getEpoch();
        uint256 _lastUpdateEpoch = lastUpdateEpoch;
        if (_lastUpdateEpoch >= epoch) return;
        while (_lastUpdateEpoch < epoch) {
            _lastUpdateEpoch++;
            uint256 toMint = calculateEmissions(_lastUpdateEpoch);
            IMinter(address(govToken)).mint(address(this), toMint);
            unallocated += toMint;
        }
        lastUpdateEpoch = epoch;
    }


    function calculateEmissions(uint256 epoch) internal returns (uint256) {
        if (epoch >= getEpoch()) return 0;
        uint256 _lastUpdateEpoch = lastUpdateEpoch;
        if (epoch - _lastUpdateEpoch > epochsPer) {
            uint256 len = emissionsSchedule.length;
            if (len > 0) {
                emissionsRate = emissionsSchedule[len - 1];
                emissionsSchedule.pop();
            }
            else {
                emissionsRate = tailRate;
            }
        }

        uint256 toMint = (
            govToken.totalSupply() * 
            emissionsRate * 
            epochLength /
            YEAR /
            PRECISION
        );
        lastEmissionsMint = block.timestamp;
        return toMint;
    }

    /**
     * @notice Sets the emissions schedule and epochs per schedule item
     * @param _schedule An array of emission rates expressed as annual pct of total supply (100% = 1e18)
     * @param _epochsPer Number of epochs each schedule item lasts
     * @dev schedule should be in reverse order. Last item will be used first.
     */
    function setEmissionsSchedule(uint256[] memory _schedule, uint256 _epochsPer, uint256 _tailRate) external onlyOwner {
        require(_schedule.length > 0, "Schedule must have at least one item");
        require(_epochsPer > 0 && _epochsPer <= 52, "Invalid epochs per");
        emissionsSchedule = _schedule;
        epochsPer = _epochsPer;
        tailRate = _tailRate;
    }

    function getEmissionsSchedule() external view returns (uint256[] memory) {
        return emissionsSchedule;
    }
}
