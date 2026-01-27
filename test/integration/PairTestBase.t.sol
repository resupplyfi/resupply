// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol, DeploymentConfig } from "src/Constants.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { console } from "lib/forge-std/src/console.sol";
import { Setup } from "test/integration/Setup.sol";
import { Utilities } from "src/protocol/Utilities.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { ResupplyPairConstants } from "src/protocol/pair/ResupplyPairConstants.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract PairTestBase is Setup, ResupplyPairConstants {

    IResupplyPair pair;
    IERC20 collateral;
    IERC20 underlying;
    Utilities utilities;

    function setUp() public virtual override {
        super.setUp();
        address[] memory _pairs = registry.getAllPairAddresses();
        pair = IResupplyPair(_pairs[0]); 
        collateral = IERC20(pair.collateral());
        underlying = IERC20(pair.underlying());
        printPairInfo(pair);

        collateral.approve(address(pair), type(uint256).max);
        underlying.approve(address(pair), type(uint256).max);
        stablecoin.approve(address(redemptionHandler), type(uint256).max);
        utilities = new Utilities(address(registry));
    }

    function deployLendingPair(uint256 _protocolId, address _collateral, address _staking, uint256 _stakingId) public returns(address){
        bytes memory configdata = abi.encode(
            _collateral,
            address(Protocol.BASIC_VAULT_ORACLE),
            address(Protocol.INTEREST_RATE_CALCULATOR),
            DeploymentConfig.DEFAULT_MAX_LTV,
            DeploymentConfig.DEFAULT_BORROW_LIMIT,
            DeploymentConfig.DEFAULT_LIQ_FEE,
            DeploymentConfig.DEFAULT_MINT_FEE,
            DeploymentConfig.DEFAULT_PROTOCOL_REDEMPTION_FEE
        );
        bytes memory immutables = abi.encode(address(Protocol.REGISTRY));

        vm.prank(address(core));
        address pair = deployer.deploy(_protocolId, configdata, _staking, _stakingId);

        string memory name = IResupplyPair(pair).name();
        bytes memory customData = abi.encode(name, address(Protocol.GOV_TOKEN), _staking, _stakingId);
        bytes memory constructorData = abi.encode(Protocol.CORE, configdata, immutables, customData);

        console.log('pair deployed: ', pair);
        console.log('collateral: ', IResupplyPair(pair).collateral());
        console.log('underlying: ', IResupplyPair(pair).underlying());
        console.log('constructor args:');
        console.logBytes(constructorData);

        return pair;
    }

    function printPairInfo(IResupplyPair _pair) public view {
        console.log("pair: ", _pair.name());
        console.log("address", address(_pair));
        console.log("collateral", address(_pair.collateral()));
        console.log("underlying", address(_pair.underlying()));
        (uint256 _borrowAmount, ) = _pair.totalBorrow();
        console.log("totalBorrowAmount: ", _borrowAmount);
    }

    function printUserInfo(IResupplyPair _pair, address _user) public {
        (uint256 borrowshares, uint256 usercollateral) = _pair.getUserSnapshot(_user);
        console.log("user borrowshares: ", borrowshares);
        console.log("user collateral: ", usercollateral);
    }

    function printPairFees(IResupplyPair _pair) internal view{
        console.log("interest fees: ", _pair.claimableFees());
        console.log("other fees: ", _pair.claimableOtherFees());
        console.log("last feedpoist claim epoch: ", feeDeposit.lastDistributedEpoch());
        console.log("last pair claim epoch: ", _pair.lastFeeEpoch());
        console.log("current epoch: ", feeDeposit.getEpoch());
    }

    function getUtilization(IResupplyPair _pair) internal view returns (uint256 _utilization) {
        (uint256 _borrowAmount, ) = _pair.totalBorrow();
        uint256 _borrowLimit = _pair.borrowLimit();
        _utilization = (_borrowAmount * EXCHANGE_PRECISION) / _borrowLimit;
    }

    function ratePerSec(IResupplyPair _pair) internal view returns (uint64 _ratePerSec) {
        (,_ratePerSec,) = _pair.currentRateInfo();
    }

    function getCurrentLTV(IResupplyPair _pair, address _user) internal returns(uint256 _ltv){
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

    function addCollateral(IResupplyPair _pair, uint256 amount) public {
        IERC20 collateral = IERC20(_pair.collateral());
        deal(address(collateral), address(this), amount);
        collateral.approve(address(_pair), type(uint256).max);
        _pair.addCollateralVault(amount, address(this));
    }

    function removeCollateral(IResupplyPair _pair, uint256 amount) public {
        uint256 startCollateralBalance = _pair.userCollateralBalance(address(this));
        _pair.removeCollateralVault(amount, address(this));
        uint256 endCollateralBalance = _pair.userCollateralBalance(address(this));
        console.log("start collateral balance: ", startCollateralBalance);
        console.log("end collateral balance: ", endCollateralBalance);
    }

    // collateralAmount is the amount of collateral to add for the borrow
    function borrow(IResupplyPair _pair, uint256 borrowAmount, uint256 underlyingAmount) public {
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

    function printEarned(IResupplyPair _pair, address _account) public{
        IResupplyPair.EarnedData[] memory eData = _pair.earned(_account);
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
