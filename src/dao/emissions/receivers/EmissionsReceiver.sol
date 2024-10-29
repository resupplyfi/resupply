// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.22;

// import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import { IEmissionsController } from "../../../interfaces/IEmissionsController.sol";
// import { EpochTracker } from "../../../dependencies/EpochTracker.sol";

// contract EmissionsReceiver is EpochTracker {
//     IEmissionsController public immutable emissionsController;
//     IERC20 public immutable govToken;
//     string public name;
//     uint256 public receiverId;
//     uint32 public epochFinish;
//     mapping(address => uint256) public storedPendingReward;
//     mapping(address => uint256) public rewardIntegralFor;
//     uint256 public rewardRate;
//     uint256 public periodFinish;
//     uint256 public lastUpdate;
//     uint256 public rewardIntegral;

//     uint256 public immutable REWARD_DURATION;

//     // TODO: Add view functions to get rewards data per user

//     constructor(address _core, address _emissionsController, string memory _name) EpochTracker(_core) {
//         emissionsController = IEmissionsController(_emissionsController);
//         govToken = IERC20(address(emissionsController.govToken()));
//         name = _name;
//         REWARD_DURATION = epochLength;
//     }

//     function getReceiverId() external view returns (uint256) {
//         uint256 _id = emissionsController.receiverToId(address(this));
//         if (_id == 0) require(emissionsController.idToReceiver(_id).receiver == address(this), "!registered");
//         return _id;
//     }

//     function claimableReward(address account) external view returns (uint256) {
//         // previously calculated rewards
//         uint256 amount = storedPendingReward[account];

//         // pending active debt rewards
//         uint256 updated = periodFinish;
//         if (updated > block.timestamp) updated = block.timestamp;
//         uint256 duration = updated - lastUpdate;
//         uint256 integral = rewardIntegral;
//         if (duration > 0) {
//             uint256 supply = totalActiveDebt;
//             if (supply > 0) {
//                 integral += (duration * rewardRate * 1e18) / supply;
//             }
//         }
//         uint256 integralFor = rewardIntegralFor[account];

//         if (integral > integralFor) {
//             amount += (accountBalance * (integral - integralFor)) / 1e18;
//         }

//         return amount;
//     }

//     function _updateIntegrals(address account, uint256 balance, uint256 supply) internal {
//         uint256 integral = _updateRewardIntegral(supply);
//         _updateIntegralForAccount(account, balance, integral);
//     }

//     function _updateIntegralForAccount(address account, uint256 balance, uint256 currentIntegral) internal {
//         uint256 integralFor = rewardIntegralFor[account];
//         if (currentIntegral > integralFor) {
//             storedPendingReward[account] += (balance * (currentIntegral - integralFor)) / 1e18;
//             rewardIntegralFor[account] = currentIntegral;
//         }
//     }

//     function _updateRewardIntegral(uint256 supply) internal returns (uint256 integral) {
//         uint256 _epochFinish = epochFinish;
//         uint256 updated = _epochFinish;
//         if (updated > block.timestamp) updated = block.timestamp;
//         uint256 duration = updated - lastUpdate;
//         integral = rewardIntegral;
//         if (duration > 0) {
//             lastUpdate = uint32(updated);
//             if (supply > 0) {
//                 integral += (duration * rewardRate * 1e18) / supply;
//                 rewardIntegral = integral;
//             }
//         }
//         _allocateEmissions(_epochFinish);

//         return integral;
//     }

//     function allocateEmissions() external {
//         _allocateEmissions();
//     }

//     function _allocateEmissions() internal {
//         // dev: should run this on all rewards actions
//         uint256 currentEpoch = getEpoch();
//         uint256 _epochFinish = epochFinish;
//         if (currentEpoch < (_epochFinish - startTime) / epochLength) return;

//         uint256 amount = emissionsController.fetchEmissions();
//         if (block.timestamp < _epochFinish) {
//             uint256 remaining = _epochFinish - block.timestamp;
//             amount += remaining * rewardRate;
//         }   
//         rewardRate = amount / REWARD_DURATION;
//         lastUpdate = block.timestamp;
//         periodFinish = block.timestamp + REWARD_DURATION;
//         // dev: do something with amount
//     }

//     function claimReward(address _recipient) external {
//         uint256 amount;
//         // TODO: Logic to determine amount claimable
//         _allocateEmissions();
//         emissionsController.transferFromAllocation(_recipient, amount);
//     }

// }

