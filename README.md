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
| `DEPLOYER_ACCOUNT`          | BaseAction | Account name used in BaseAction for deployment scripts                                |
| `DEPLOYER_PASSWORD`         | BaseAction | Password for the deployer account (optional, bypasses keystore prompt)                |
| `WALLET_TYPE`               | SafeHelper | Tells SafeHelper which type of account to use (options: "local", "ledger", "account") |
| `SAFE_PROPOSER_ACCOUNT`     | SafeHelper | Account name used in SafeHelper when walletType="account"                             |
| `SAFE_PROPOSER_PASSWORD`    | SafeHelper | Password for the safe proposer account (optional, bypasses keystore prompt)           |
| `SAFE_PROPOSER_PRIVATE_KEY` | SafeHelper | Private key used in SafeHelper when walletType="local"                                |
| `MAINNET_URL`               | Network    | RPC URL for mainnet                                                                   |
| `SOLX_PATH`                 | Network    | Path to solx binary                                                                   |
| `ETHERSCAN_API_KEY`         | Network    | API key for Etherscan verification                                                    |

## Security

### Audits

- yAudit
- Chain Security

## License

MIT License

## Documentation

For detailed protocol documentation, visit [docs.resupply.fi](https://docs.resupply.fi)
