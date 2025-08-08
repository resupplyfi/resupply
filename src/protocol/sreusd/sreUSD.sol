// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { OFTCore } from "@layerzerolabs/oft-evm/contracts/OFTCore.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeCastLib } from "src/libraries/solmate/SafeCastLib.sol";
import { LinearRewardsErc4626, ERC20 } from "./LinearRewardsErc4626.sol";

/**
 * @title Savings reUSD
 * @notice ERC4626 Vault implementation with linear rewards, adapted from code from Frax Finance's sfrxUSD
 */
contract SavingsReUSD is LinearRewardsErc4626, OFTCore {
    using SafeCastLib for *;

    /// @notice The maximum amount of rewards that can be distributed per second per 1e18 asset
    uint256 public maxDistributionPerSecondPerAsset;

    /// @param _core The core address
    /// @param _registry The registry address
    /// @param _lzEndpoint The layerzero endpoint address
    /// @param _underlying The erc20 asset deposited
    /// @param _name The name of the vault
    /// @param _symbol The symbol of the vault
    /// @param _maxDistributionPerSecondPerAsset The maximum amount of rewards that can be distributed per second per 1e18 asset
    constructor(
        address _core,
        address _registry,
        address _lzEndpoint,
        address _underlying,
        string memory _name,
        string memory _symbol,
        uint256 _maxDistributionPerSecondPerAsset
    )
        LinearRewardsErc4626(_core, _registry, _underlying, _name, _symbol, 7 days)
        OFTCore(IERC20Metadata(_underlying).decimals(), _lzEndpoint, _core)
        Ownable(_core)
    {
        if (_maxDistributionPerSecondPerAsset > type(uint64).max) _maxDistributionPerSecondPerAsset = type(uint64).max;
        maxDistributionPerSecondPerAsset = _maxDistributionPerSecondPerAsset;
        emit SetMaxDistributionPerSecondPerAsset(0, _maxDistributionPerSecondPerAsset);
    }

    function core() external view returns(address) {
        return owner();
    }

    function _transferOwnership(address newOwner) internal override {
        if(owner() == address(0)){
            super._transferOwnership(newOwner);
        }else{
            revert OwnableInvalidOwner(newOwner);
        }
    }

    /// @notice The ```SetMaxDistributionPerSecondPerAsset``` event is emitted when the maxDistributionPerSecondPerAsset is set
    /// @param oldMax The old maxDistributionPerSecondPerAsset value
    /// @param newMax The new maxDistributionPerSecondPerAsset value
    event SetMaxDistributionPerSecondPerAsset(uint256 oldMax, uint256 newMax);

    /// @notice The ```setMaxDistributionPerSecondPerAsset``` function sets the maxDistributionPerSecondPerAsset
    /// @dev This function can only be called by the Owner, caps the value to type(uint64).max
    /// @param _maxDistributionPerSecondPerAsset The maximum amount of rewards that can be distributed per second per 1e18 asset
    function setMaxDistributionPerSecondPerAsset(uint256 _maxDistributionPerSecondPerAsset) external onlyOwner{
        syncRewardsAndDistribution();

        // NOTE: prevents bricking the contract via overflow
        if (_maxDistributionPerSecondPerAsset > type(uint64).max) {
            _maxDistributionPerSecondPerAsset = type(uint64).max;
        }

        emit SetMaxDistributionPerSecondPerAsset({
            oldMax: maxDistributionPerSecondPerAsset,
            newMax: _maxDistributionPerSecondPerAsset
        });

        maxDistributionPerSecondPerAsset = _maxDistributionPerSecondPerAsset;
    }

    /// @notice The ```calculateRewardsToDistribute``` function calculates the amount of rewards to distribute based on the rewards cycle data and the time passed
    /// @param _rewardsCycleData The rewards cycle data
    /// @param _deltaTime The time passed since the last rewards distribution
    /// @return _rewardToDistribute The amount of rewards to distribute
    function calculateRewardsToDistribute(
        RewardsCycleData memory _rewardsCycleData,
        uint256 _deltaTime
    ) public view override returns (uint256 _rewardToDistribute) {
        _rewardToDistribute = super.calculateRewardsToDistribute({
            _rewardsCycleData: _rewardsCycleData,
            _deltaTime: _deltaTime
        });

        // Cap rewards
        uint256 _maxDistribution = (maxDistributionPerSecondPerAsset * _deltaTime * storedTotalAssets) / PRECISION;
        if (_rewardToDistribute > _maxDistribution) {
            _rewardToDistribute = _maxDistribution;
        }
    }



    ////////////////
    // OFT Implementation
    ////////////////

    /**
     * @dev Retrieves the address of the underlying ERC20 implementation.
     * @return The address of the OFT token.
     *
     * @dev In the case of OFT, address(this) and erc20 are the same contract.
     */
    function token() public view returns (address) {
        return address(this);
    }

    /**
     * @notice Indicates whether the OFT contract requires approval of the 'token()' to send.
     * @return requiresApproval Needs approval of the underlying token implementation.
     *
     * @dev In the case of OFT where the contract IS the token, approval is NOT required.
     */
    function approvalRequired() external pure virtual returns (bool) {
        return false;
    }

    /**
     * @dev Burns tokens from the sender's specified balance.
     * @param _from The address to debit the tokens from.
     * @param _amountLD The amount of tokens to send in local decimals.
     * @param _minAmountLD The minimum amount to send in local decimals.
     * @param _dstEid The destination chain ID.
     * @return amountSentLD The amount sent in local decimals.
     * @return amountReceivedLD The amount received in local decimals on the remote.
     */
    function _debit(
        address _from,
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) internal virtual override returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        (amountSentLD, amountReceivedLD) = _debitView(_amountLD, _minAmountLD, _dstEid);

        // @dev In NON-default OFT, amountSentLD could be 100, with a 10% fee, the amountReceivedLD amount is 90,
        // therefore amountSentLD CAN differ from amountReceivedLD.

        //for 4626 vault we cant burn/mint and change supply
        //transfer the tokens to this contract instead

        //reduce balance of _from
        balanceOf[_from] -= amountSentLD;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[address(this)] += amountSentLD;
        }

        emit Transfer(_from, address(this), amountSentLD);
    }

    /**
     * @dev Credits tokens to the specified address.
     * @param _to The address to credit the tokens to.
     * @param _amountLD The amount of tokens to credit in local decimals.
     * @dev _srcEid The source chain ID.
     * @return amountReceivedLD The amount of tokens ACTUALLY received in local decimals.
     */
    function _credit(
        address _to,
        uint256 _amountLD,
        uint32 /*_srcEid*/
    ) internal virtual override returns (uint256 amountReceivedLD) {
        if (_to == address(0x0)) _to = address(0xdead); // _mint(...) does not support address(0x0)

        //for 4626 vault we cant burn/mint and change supply
        //transfer tokens from this contract instead
        //reduce balance of this contract, will revert if there is not enough cached
        balanceOf[address(this)] -= _amountLD;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            //increase balance of _to
            balanceOf[_to] += _amountLD;
        }

        emit Transfer(address(this), _to, _amountLD);

        // @dev In the case of NON-default OFT, the _amountLD MIGHT not be == amountReceivedLD.
        return _amountLD;
    }
}
