// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "src/Constants.sol" as Constants;
import { console } from "lib/forge-std/src/console.sol";
import { Utilities } from "src/protocol/Utilities.sol";
import { ResupplyPair } from "src/protocol/ResupplyPair.sol";
import { ResupplyPairConstants } from "src/protocol/pair/ResupplyPairConstants.sol";
import { Setup } from "test/Setup.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract PairTestBase is Setup, ResupplyPairConstants {

    ResupplyPair pair;
    IERC20 collateral;
    IERC20 underlying;
    Utilities utilities;

    function setUp() public virtual override {
        super.setUp();

        deployDefaultLendingPairs();
        address[] memory _pairs = registry.getAllPairAddresses();
        pair = ResupplyPair(_pairs[0]); 
        collateral = pair.collateral();
        underlying = pair.underlying();
        printPairInfo(pair);

        collateral.approve(address(pair), type(uint256).max);
        underlying.approve(address(pair), type(uint256).max);
        stablecoin.approve(address(redemptionHandler), type(uint256).max);
        utilities = new Utilities(address(registry));
    }

    function addSwapLiquidity() public{
        deal(address(stablecoin), address(this), 200_000_000e18);
        deal(address(frxusdToken), address(this), 100_000_000e18);
        deal(address(crvusdToken), address(this), 100_000_000e18);
        IERC4626 scrvusdvault = IERC4626(Constants.Mainnet.CURVE_SCRVUSD);
        IERC4626 sfrxusdvault = IERC4626(Constants.Mainnet.SFRXUSD_ERC20);
        frxusdToken.approve(address(sfrxusdvault), type(uint256).max);
        crvusdToken.approve(address(scrvusdvault), type(uint256).max);
        scrvusdvault.deposit(100_000_000e18, address(this));
        sfrxusdvault.deposit(100_000_000e18, address(this));

        IERC20 scrvusd = IERC20(Constants.Mainnet.CURVE_SCRVUSD);
        IERC20 sfrxusd = IERC20(Constants.Mainnet.SFRXUSD_ERC20);

        scrvusd.approve(address(swapPoolsCrvUsd), type(uint256).max);
        stablecoin.approve(address(swapPoolsCrvUsd), type(uint256).max);
        sfrxusd.approve(address(swapPoolsFrxusd), type(uint256).max);
        stablecoin.approve(address(swapPoolsFrxusd), type(uint256).max);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100_000_000e18;
        amounts[1] = scrvusd.balanceOf(address(this));

        swapPoolsCrvUsd.add_liquidity(amounts,0,address(this));

        amounts[1] = sfrxusd.balanceOf(address(this));
        swapPoolsFrxusd.add_liquidity(amounts,0,address(this));
    }

    function printPairInfo(ResupplyPair _pair) public view {
        console.log("pair: ", _pair.name());
        console.log("address", address(_pair));
        console.log("collateral", address(_pair.collateral()));
        console.log("underlying", address(_pair.underlying()));
        (uint256 _borrowAmount, ) = _pair.totalBorrow();
        console.log("totalBorrowAmount: ", _borrowAmount);
    }

    function printUserInfo(ResupplyPair _pair, address _user) public {
        (uint256 borrowshares, uint256 usercollateral) = _pair.getUserSnapshot(_user);
        console.log("user borrowshares: ", borrowshares);
        console.log("user collateral: ", usercollateral);
    }

    function printPairFees(ResupplyPair _pair) internal view{
        console.log("interest fees: ", _pair.claimableFees());
        console.log("other fees: ", _pair.claimableOtherFees());
        console.log("last feedpoist claim epoch: ", feeDeposit.lastDistributedEpoch());
        console.log("last pair claim epoch: ", _pair.lastFeeEpoch());
        console.log("current epoch: ", feeDeposit.getEpoch());
    }

    function getUtilization(ResupplyPair _pair) internal view returns (uint256 _utilization) {
        (uint256 _borrowAmount, ) = _pair.totalBorrow();
        uint256 _borrowLimit = _pair.borrowLimit();
        _utilization = (_borrowAmount * EXCHANGE_PRECISION) / _borrowLimit;
    }

    function ratePerSec(ResupplyPair _pair) internal view returns (uint64 _ratePerSec) {
        (,_ratePerSec,) = _pair.currentRateInfo();
    }

    function getCurrentLTV(ResupplyPair _pair, address _user) internal returns(uint256 _ltv){
        uint256 _borrowerAmount = _pair.toBorrowAmount(_pair.userBorrowShares(_user), true, true);
        (,,uint256 _exchangeRate) = _pair.exchangeRateInfo();
        uint256 _collateralAmount = _pair.userCollateralBalance(_user);
        _ltv = (((_borrowerAmount * _exchangeRate) / EXCHANGE_PRECISION) * LTV_PRECISION) / _collateralAmount;
    }

    function getCollateralAmount(
        uint256 _borrowAmount,
        uint256 _exchangeRate,
        uint256 _targetLTV
    ) internal pure returns (uint256 _collateralAmount) {
        _collateralAmount = (_borrowAmount * _exchangeRate * LTV_PRECISION) / (_targetLTV * EXCHANGE_PRECISION);
    }

    function addCollateral(ResupplyPair _pair, uint256 amount) public {
        IERC20 collateral = _pair.collateral();
        deal(address(collateral), address(this), amount);
        _pair.addCollateralVault(amount, address(this));
    }

    function removeCollateral(ResupplyPair _pair, uint256 amount) public {
        uint256 startCollateralBalance = _pair.userCollateralBalance(_THIS);
        _pair.removeCollateralVault(amount, address(this));
    }

    // collateralAmount is the amount of collateral to add for the borrow
    function borrow(ResupplyPair _pair, uint256 borrowAmount, uint256 underlyingAmount) public {
        if (underlyingAmount > underlying.balanceOf(address(this))) deal(address(underlying), address(this), underlyingAmount);
        _pair.borrow(borrowAmount, underlyingAmount, address(this));
    }

    function convertToShares(address token, uint256 amount) public view returns (uint256) {
        return IERC4626(token).convertToShares(amount);
    }

    function convertToAssets(address token, uint256 shares) public view returns (uint256) {
        return IERC4626(token).convertToAssets(shares);
    }

    function calculateMinUnderlyingNeededForBorrow(uint256 borrowAmount) public view returns (uint256) {
        return borrowAmount * ResupplyPairConstants.LTV_PRECISION / pair.maxLTV();
    }

    function printEarned(ResupplyPair _pair, address _account) public{
        ResupplyPair.EarnedData[] memory eData = _pair.earned(_account);
        uint256 len = eData.length;
        console.log("--- earned ---");
        for(uint256 i=0; i < len; i++){
            console.log("token: ", eData[i].token);
            IERC20Metadata meta = IERC20Metadata(eData[i].token);
            console.log("token name: ", meta.name());
            console.log("amount: ", eData[i].amount);
        }
        console.log("-----------");
    }
}
