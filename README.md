# Resupply Finance Protocol

## Overview

Resupply is a CDP-based stablecoin protocol that enables users to maximize yield on their stablecoin lending positions.

## Development Setup

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)

### Build

```shell
forge build
```

### Test

```shell
forge test
```

## Environment Variables

This project uses several environment variables for deployment and configuration. Create a `.env` file in the root directory with the following variables:

| Variable Name               | Usage      | Description                                                                           |
| --------------------------- | ---------- | ------------------------------------------------------------------------------------- |
| `WALLET_TYPE`               | SafeHelper | Tells SafeHelper which type of account to use (options: "local", "ledger", "account") |
| `SAFE_PROPOSER_ACCOUNT`     | SafeHelper | Account name used in SafeHelper when walletType="account"                             |
| `SAFE_PROPOSER_PASSWORD`    | SafeHelper | Password for the safe proposer account (optional, bypasses keystore prompt)           |
| `SAFE_PROPOSER_PRIVATE_KEY` | SafeHelper | Private key used in SafeHelper when walletType="local"                                |
| `KEEPER_OWNER`              | Deployment | Optional owner override for `DeployKeeper`; defaults to `Protocol.DEPLOYER`           |
| `MAINNET_URL`               | Network    | RPC URL for mainnet                                                                   |
| `SOLX_PATH`                 | Network    | Path to solx binary                                                                   |
| `ETHERSCAN_API_KEY`         | Network    | API key for Etherscan verification                                                    |

Deployment scripts that broadcast transactions should use Foundry's native wallet flags:

```shell
forge script script/actions/DeployRouterSwappers.s.sol:DeployRouterSwappers \
  --rpc-url "$MAINNET_URL" \
  --broadcast \
  --account <foundry-keystore-account>
```

## Security

### Audits

- yAudit
- Chain Security

## License

MIT License

## Documentation

For detailed protocol documentation, visit [docs.resupply.fi](https://docs.resupply.fi)
