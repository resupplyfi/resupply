## Resupply

Rework of Prisma platform

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

## Summary

Create a new CDP-based stable coin with the aim of serving as a utility coin that encourages the use of underlying stables like crvUSD and FRAX, rather than aiming to become a dominant player in the stablecoin markets.

## CDP Logic

The CDP's logic could consist of a fork of Fraxlend. There are changes to how liquidations work, the addition of redemptions, a reward system, and a single supplier based system.

### Changes to fraxlend:

- Remove clean/dirty liquidation fees, always do full liquidation
- Remove bad debt write off as protocol is only issuer
- Remove erc4626 interface for supplying as protocol is only issuer
- Remove deposit limit
- Interest accrues to a claimableFees parameter instead of accruing to supply shares
- Remove erc20 aspects
- Simplify admin controls, change to registry or registry.owner
- Liquidation must enter via a liquidation handler and collateral is sent to that handler to be processed down the line(burn stables from insurance pool while distributing the collateral)
- Change withdraw fee to match our flow. Only claimable once per epoch and after our main fee deposit contract has distributed for the current epoch
- Use mint and burn instead of stables supplied to the pair
- Add a reward distribution system based on borrow supply
- Add redemptions where anyone can supply stables (to be burnt) and receive collateral in return. Borrowers debt is reduced
- Create a “write off” token reward to be distributed to borrowers during redemptions. Collateral can't be share based since everyone has a different tlv ratio. Use the write off tokens to remove user collateral based on their share of debt.
- Change rate calculator to use the change in value of the underlying collateral and take a % of that. Aka if collateral is 10% Apr then charge 5% interest rate.
- New simple oracle to just look at convertSharesToAssets
- Add collateral via underlying for ease of use
- Remove writing to “totalCollateral” and just read how much collateral is there
- Allow staking underlying on convex
- Add a minimum amount of assets that must be left on the pair during redemptions (don't allow assets to go to 0)
- Add a share refactoring system if assets to shares ratio deteriorates too far from too many redemptions
- Add a minimum borrow settings that you must borrow. Repayment should also force a full repayment if going below the minimum
- Add a mint fee (not exactly planned to use but might be good to have just in case)
- Rearrange deployer/registry design to fit our flow a bit better
- Todo: consider flow on a pair shutdown
- Todo: consider removing some access control variables such as the ones that make certain settings immutable(ex.isWithdrawAccessControlRevoked). All changes will always go through dao votes.
