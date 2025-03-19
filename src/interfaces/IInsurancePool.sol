// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IInsurancePool {
    event Deposit(
        address indexed sender,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    event Withdraw(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256 shares,
        uint256 assets
    );

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Cooldown(address indexed account, uint256 amount, uint256 end);
    event ExitCancel(address indexed account);
    event WithdrawTimersUpdated(uint256 withdrawTime, uint256 withdrawWindow);
    event MinimumHeldAssetsUpdated(uint256 minimumAssets);

    // Constants
    function SHARE_REFACTOR_PRECISION() external pure returns (uint256);
    function MAX_WITHDRAW_DELAY() external pure returns (uint256);

    // View/Pure functions
    function asset() external view returns (address);
    function registry() external view returns (address);
    function name() external pure returns (string memory);
    function symbol() external pure returns (string memory);
    function decimals() external pure returns (uint8);
    function minimumHeldAssets() external view returns (uint256);
    function withdrawTime() external view returns (uint256);
    function withdrawTimeLimit() external view returns (uint256);
    function withdrawQueue(address) external view returns (uint256);
    function emissionsReceiver() external view returns (address);
    function totalSupply() external view returns (uint256);
    function balanceOf(address _account) external view returns (uint256);
    function maxRewards() external pure returns (uint256);
    function maxBurnableAssets() external view returns (uint256);
    function totalAssets() external view returns (uint256);
    function convertToShares(uint256 _assets) external view returns (uint256);
    function convertToAssets(uint256 _shares) external view returns (uint256);
    function maxDeposit(address _receiver) external pure returns (uint256);
    function maxMint(address _receiver) external pure returns (uint256);
    function previewDeposit(uint256 _amount) external view returns (uint256);
    function previewMint(uint256 _shares) external view returns (uint256);
    function maxWithdraw(address _owner) external view returns (uint256);
    function previewWithdraw(uint256 _amount) external view returns (uint256);
    function maxRedeem(address _owner) external view returns (uint256);
    function previewRedeem(uint256 _shares) external view returns (uint256);

    // State-changing functions
    function setWithdrawTimers(uint256 _withdrawLength, uint256 _withdrawWindow) external;
    function setMinimumHeldAssets(uint256 _minimum) external;
    function burnAssets(uint256 _amount) external;
    function deposit(uint256 _assets, address _receiver) external returns (uint256);
    function mint(uint256 _shares, address _receiver) external returns (uint256);
    function exit() external;
    function cancelExit() external;
    function redeem(uint256 _shares, address _receiver, address _owner) external returns (uint256);
    function withdraw(uint256 _amount, address _receiver, address _owner) external returns (uint256);
    function getReward(address _account) external;
    function getReward(address _account, address _forwardTo) external;

    // Structs needed for earned() function
    struct EarnedData {
        address token;
        uint256 amount;
    }
    function earned(address _account) external returns (EarnedData[] memory);
}