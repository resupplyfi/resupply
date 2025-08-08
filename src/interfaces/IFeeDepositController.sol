// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title IFeeDepositController
/// @notice Interface for the FeeDepositController contract that handles distribution of fees
interface IFeeDepositController {
    /// @notice Struct defining the split percentages for fee distribution
    struct Splits {
        uint40 insurance;
        uint40 treasury;
        uint40 platform;
        uint40 stakedStable;
    }

    /// @notice Emitted when fee distribution splits are updated
    /// @param insurance The percentage (in BPS) allocated to insurance pool
    /// @param treasury The percentage (in BPS) allocated to treasury
    /// @param platform The percentage (in BPS) allocated to platform stakers
    event SplitsSet(uint40 insurance, uint40 treasury, uint40 platform, uint40 stakedStable);
    event AdditionalFeeRatioSet(uint256 ratio);

    /// @notice Returns the address of the registry contract
    function registry() external view returns (address);

    /// @notice Returns the address of the treasury
    function treasury() external view returns (address);

    /// @notice Returns the address of the fee deposit contract
    function feeDeposit() external view returns (address);

    /// @notice Returns the address of the fee token
    function feeToken() external view returns (address);

    /// @notice Returns the basis points constant (10,000)
    function BPS() external view returns (uint256);

    /// @notice Returns the current split configuration
    function splits() external view returns (Splits memory);

    /// @notice Distributes collected fees according to the configured splits
    function distribute() external;

    /// @notice Sets the fee distribution splits between insurance, treasury, and platform
    /// @param _insuranceSplit The percentage (in BPS) to send to insurance pool
    /// @param _treasurySplit The percentage (in BPS) to send to treasury
    /// @param _platformSplit The percentage (in BPS) to send to platform stakers
    /// @param _stakedStableSplit The percentage (in BPS) to send to staked stable
    function setSplits(uint256 _insuranceSplit, uint256 _treasurySplit, uint256 _platformSplit, uint256 _stakedStableSplit) external;


    function setAdditionalFeeRatio(uint256 _additionalFee) external;

    /// @notice Returns the maximum additional fee ratio
    function additionalFeeRatio() external view returns (uint256);

}