import { console } from "forge-std/console.sol";
import { ResupplyPair } from "src/protocol/ResupplyPair.sol";
import { RewardDistributorMultiEpoch } from "src/protocol/RewardDistributorMultiEpoch.sol";
import { Setup } from "test/Setup.sol";
import { PairTestBase } from "./PairTestBase.t.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract PairTestFeeFlow is PairTestBase {
    ResupplyPair pair;
    IERC20 collateral;
    IERC20 underlying;

    function setUp() public override {
        super.setUp();

        deployDefaultLendingPairs();
        address[] memory _pairs = registry.getAllPairAddresses();
        pair = ResupplyPair(_pairs[0]); 
        collateral = pair.collateral();
        underlying = pair.underlying();
        printPairInfo(pair);

        collateral.approve(address(pair), type(uint256).max);
        underlying.approve(address(pair), type(uint256).max);
    }

    /*
    queue up fees on pair
    distro fee deposit
    queue up new fees
    distro next week fee deposit

    check gov token staking token rates
    check insurance pool token rates
    check treasury token amount
    check pair weightings
    check pair emission rates
    check pair earned()
    */
    function test_feeFlow() public {
        assertEq(pair.userCollateralBalance(_THIS), 0);

        deal(address(stakingToken), address(this), 1e18);
        stakingToken.approve(address(staker), 1e18);
        staker.stake(address(this), 1e18);
        assertEq(staker.balanceOf(_THIS), 1e18);

        printPairFees(pair);
        vm.warp(block.timestamp + 7 days);
        printPairFees(pair);
        feeDepositController.distribute();
        pair.withdrawFees();

        uint256 maxltv = pair.maxLTV();
        uint256 availableDebt = pair.totalDebtAvailable();
        (,,uint256 exchangeRate) = pair.exchangeRateInfo();

        uint256 collateralAmount = getCollateralAmount(availableDebt,exchangeRate,maxltv);
        deal(address(collateral), address(this), collateralAmount);

        // pair.addCollateralVault(amount, address(this));
        borrow(pair, availableDebt, collateralAmount);
        console.log("\nborrowed\n");
        assertEq(pair.userCollateralBalance(_THIS), collateralAmount);
        

        vm.warp(block.timestamp +7 days);
        pair.addInterest(false);

        printPairFees(pair);
        printDistributionInfo();
        feeDepositController.distribute();
        pair.withdrawFees();
        console.log("\nclaimed fees\n");
        printPairFees(pair);
        printDistributionInfo();

        console.log("\nwarp to next week now that these are queued\n");

        vm.warp(block.timestamp +7 days);
        pair.addInterest(false);

        printPairFees(pair);
        printDistributionInfo();
        feeDepositController.distribute();
        pair.withdrawFees();
        console.log("\nclaimed fees\n");
        printPairFees(pair);
        printDistributionInfo();

        vm.warp(block.timestamp +1 days);
        console.log("\nwarp to check claimables\n");
        printDistributionInfo();

        RewardDistributorMultiEpoch.EarnedData[] memory earnedData = pair.earned(address(this));
        console.log("govToken rewards before claim: ", stakingToken.balanceOf(address(this)));
        pair.getReward(address(this));
        console.log("govToken rewards after claim: ", stakingToken.balanceOf(address(this)));

        //the claimable amount should equal what was actually claimed
        assertEq(earnedData[0].amount, stakingToken.balanceOf(address(this)));
    }

    function printDistributionInfo() internal{
        console.log("stables on feeDeposit: ", stablecoin.balanceOf(address(feeDeposit)));
        console.log("stables on gov staker: ", stablecoin.balanceOf(address(staker)));
        console.log("stables on treasury: ", stablecoin.balanceOf(address(treasury)));
        console.log("stables on insurance: ", stablecoin.balanceOf(address(insurancePool)));
        console.log("stables on insurance distribution: ", stablecoin.balanceOf(address(ipStableStream)));
        console.log("govToken on insurance: ", stakingToken.balanceOf(address(insurancePool)));
        console.log("govToken on insurance distribution: ", stakingToken.balanceOf(address(ipEmissionStream)));
        console.log("govToken on pair emissions: ", stakingToken.balanceOf(address(pairEmissionStream)));
        console.log("govToken on pair: ", stakingToken.balanceOf(address(pair)));

        (,,,uint256 rate,,) = staker.rewardData(address(stablecoin));
        console.log("stables reward rate on gov staker: ",rate);
        console.log("stables reward rate on insurancepool: ", ipStableStream.rewardRate());
        console.log("emission reward rate on insurancepool: ", ipEmissionStream.rewardRate());
        console.log("emission reward rate for all pairs: ", pairEmissionStream.rewardRate());
        console.log("weight of current pair: ", pairEmissionStream.balanceOf(address(pair)));
        console.log("total pair weight: ", pairEmissionStream.totalSupply());
        console.log("emissions earned by pair: ", pairEmissionStream.earned(address(pair)));
        RewardDistributorMultiEpoch.EarnedData[] memory earnedData = pair.earned(address(this));
        uint256 rlength =  earnedData.length;
        console.log("earned length: ", rlength);
        for(uint256 i = 0; i < rlength; i++){
            console.log("earned token: ", earnedData[i].token, ", amount: ", earnedData[i].amount);
        }
        //earned should have claimed all emissions for the pair
       assertEq(pairEmissionStream.earned(address(pair)), 0);
    }
}
