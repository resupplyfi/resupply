import { console } from "forge-std/console.sol";
import { ResupplyPair } from "src/protocol/ResupplyPair.sol";
import { ResupplyPairConstants } from "src/protocol/pair/ResupplyPairConstants.sol";
import { Setup } from "test/Setup.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract PairTestBase is Setup, ResupplyPairConstants {

    ResupplyPair pair;
    IERC20 collateral;
    IERC20 underlying;

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
    }

    function printPairInfo(ResupplyPair _pair) public view {
        console.log("pair: ", _pair.name());
        console.log("address", address(_pair));
        console.log("collateral", address(_pair.collateral()));
        console.log("underlying", address(_pair.underlying()));
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
}
