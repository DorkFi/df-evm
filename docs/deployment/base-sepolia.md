# Base Sepolia Deployment

This document describes how to deploy DorkFi LendingPoolV2 and MockOracle to Base Sepolia testnet.

---

## 1) Prerequisites

### Network

| Property           | Value                                                          |
| ------------------ | -------------------------------------------------------------- |
| **Chain ID**       | 84532                                                          |
| **RPC URL**        | `https://sepolia.base.org`                                     |
| **Explorer**       | [sepolia.basescan.org](https://sepolia.basescan.org)           |
| **Explorer (alt)** | [sepolia-explorer.base.org](https://sepolia-explorer.base.org) |

### Deployer

- **Wallet**: EVM-compatible wallet (e.g. MetaMask, Coinbase Wallet)
- **ETH**: Base Sepolia ETH for gas (deployment uses ~0.000006 ETH)
- **Private key**: Set `PRIVATE_KEY` for the deployer (or pass `--private-key`).

### Faucets (Base Sepolia ETH)

| Faucet       | URL                                                                                        |
| ------------ | ------------------------------------------------------------------------------------------ |
| Coinbase CDP | [portal.cdp.coinbase.com/products/faucet](https://portal.cdp.coinbase.com/products/faucet) |
| Alchemy      | [basefaucet.com](https://basefaucet.com/)                                                  |
| Superchain   | [app.optimism.io/faucet](https://app.optimism.io/faucet)                                   |
| thirdweb     | [thirdweb.com/base-sepolia-testnet](https://thirdweb.com/base-sepolia-testnet)             |
| PonziFun     | [testnet.ponzi.fun/faucet](https://testnet.ponzi.fun/faucet)                               |

---

## 2) Deploy & Setup (Quick Start)

**Prerequisites:** Create `.env` with `PRIVATE_KEY=0x...` (your deployer private key).

```bash
source .env

# deploy
forge script script/LendingPoolV2.s.sol:LendingPoolV2Script \
  --rpc-url https://sepolia.base.org \
  --broadcast \
  --chain-id 84532 \
  --private-key $PRIVATE_KEY

# setup (create markets + set oracle prices)
# Use addresses from the deploy broadcast output, or the Known Deployments table below
LENDING_POOL_ADDRESS=0xd3440f7dF6c8179998fE48aDa1DF39F29E783605 \
ORACLE_ADDRESS=0x6A2EF15C986B569D6DCB48E13fd268889858E07b \
forge script script/LendingPoolV2Config.s.sol:LendingPoolV2ConfigScript \
  --rpc-url https://sepolia.base.org \
  --broadcast \
  --chain-id 84532 \
  --private-key $PRIVATE_KEY
```

> **Note:** The setup script must be run with the same private key as the deployer (pool owner). Use the addresses from your deploy broadcast; the ones above are from a known deployment.

---

## 3) Deploy Core Contracts (Manual)

### Build

```bash
forge build
```

### Deploy

```bash
export PRIVATE_KEY=0x...   # your deployer private key

forge script script/LendingPoolV2.s.sol:LendingPoolV2Script \
  --rpc-url https://sepolia.base.org \
  --broadcast \
  --chain-id 84532
```

**Or with inline env:**

```bash
PRIVATE_KEY=0x... forge script script/LendingPoolV2.s.sol:LendingPoolV2Script \
  --rpc-url https://sepolia.base.org \
  --broadcast \
  --chain-id 84532
```

### Deployed Contracts

| Contract          | Description                                                    |
| ----------------- | -------------------------------------------------------------- |
| **MockOracle**    | Mock price oracle; returns `setPrice` values or defaults to $1 |
| **LendingPoolV2** | Core lending pool; receives oracle address in constructor      |

Deployment order: MockOracle → LendingPoolV2

### Known Deployments (Base Sepolia)

| Contract          | Address                                                                                                                         | Tx                                                                                                               |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| **MockOracle**    | [`0x6A2EF15C986B569D6DCB48E13fd268889858E07b`](https://sepolia.basescan.org/address/0x6A2EF15C986B569D6DCB48E13fd268889858E07b) | [0x5a163...](https://sepolia.basescan.org/tx/0x5a163559023dfc6a99449074e71288495f36cee042cb80ee428a6a311e0debd3) |
| **LendingPoolV2** | [`0xd3440f7dF6c8179998fE48aDa1DF39F29E783605`](https://sepolia.basescan.org/address/0xd3440f7dF6c8179998fE48aDa1DF39F29E783605) | [0xe12a7...](https://sepolia.basescan.org/tx/0xe12a7933b138b1cb915dbb62bb401ffc16a73949d88abd0c25cb910e980723e8) |

Deployed at block 37412813.

### Output

- Broadcast data: `broadcast/LendingPoolV2.s.sol/84532/run-latest.json`
- Deployed addresses are in the broadcast JSON

---

## 4) Optional: Verify on BaseScan

Add `--verify` and an API key:

```bash
forge script script/LendingPoolV2.s.sol:LendingPoolV2Script \
  --rpc-url https://sepolia.base.org \
  --broadcast \
  --chain-id 84532 \
  --verify \
  --etherscan-api-key <BASESCAN_API_KEY>
```

Get an API key from [sepolia.basescan.org/myapikey](https://sepolia.basescan.org/myapikey).

---

## 5) Post-Deployment: Create Markets

After deployment, the owner must call `createMarket` for each asset. The script does not create markets by default.

### Example: Create Markets

```solidity
LendingPoolV2.MarketParams memory params = LendingPoolV2.MarketParams({
    borrowRate: 0.05e18,
    slope: 0.10e18,
    reserveFactor: 0.10e18,
    collateralFactorBps: 8000,
    liquidationThresholdBps: 8500,
    closeFactorBps: 5000,
    liquidationBonusBps: 500
});

pool.createMarket(USDC_ADDRESS, params);
pool.createMarket(WETH_ADDRESS, params);
```

### Base Sepolia Token Addresses

| Token     | Address                                      | Notes                                                                                       |
| --------- | -------------------------------------------- | ------------------------------------------------------------------------------------------- |
| USDC      | `0x036CbD53842c5426634e7929541eC2318f3dCF7e` | [Explorer](https://sepolia.basescan.org/address/0x036CbD53842c5426634e7929541eC2318f3dCF7e) |
| cbBTC     | `0xcbB7C0006F23900c38EB856149F799620fcb8A4a` | [Explorer](https://sepolia.basescan.org/address/0xcbB7C0006F23900c38EB856149F799620fcb8A4a) |
| EURC      | `0x808456652fdb597867f38412077A9182bf77359F` | [Explorer](https://sepolia.basescan.org/address/0x808456652fdb597867f38412077A9182bf77359F) |
| MockERC20 | Deploy your own                              | Use `src/mocks/MockERC20.sol` for testing                                                   |

### Set Oracle Prices

Before deposits/borrows, the oracle must have prices for each market:

```solidity
// Via MockOracle
oracle.setPrice(marketId, price);  // price in 8 decimals (e.g. 2000e8 = $2000 for ETH)
```

### Market Creation Flow

1. Deploy MockOracle and LendingPoolV2.
2. With `pool.createMarket(token, params)`:
   - Create markets for USDC, WETH (or mock tokens).
3. Set prices for each market via `MockOracle.setPrice(marketId, price)`.
4. Markets start paused until a price is set; ensure prices are set before use.

---

## 6) UI Config

Config for the frontend to connect to this network. Other networks (e.g. Base mainnet) use the same schema.

### JSON (copy into `src/config/networks.ts` or equivalent)

```json
{
  "chainId": 84532,
  "name": "Base Sepolia",
  "rpcUrl": "https://sepolia.base.org",
  "blockExplorer": "https://sepolia.basescan.org",
  "contracts": {
    "lendingPool": "0x8045c02eCd91E8ff98BE8B49277730c0781D2215",
    "oracle": "0x74F6246AF46d21D1bC68a57A5934A42BB4F8EBdD",
    "stoken": "0xC6eAc98D9135757E7f36150C1EFf0eB76276f6B7"
  },
  "tokens": {
    "0xEC39F43632c681aebAdcab6C1c828bE8Fe723D7F": {
      "symbol": "USDC",
      "decimals": 6
    },
    "0x5B39E3Ac93007e0F784E13C82AD8a4591B4c4545": {
      "symbol": "cbBTC",
      "decimals": 8
    },
    "0xa9bDDa6528992e962e57D32eE0CAF493b526b0C2": {
      "symbol": "EURC",
      "decimals": 6
    },
    "0xC6eAc98D9135757E7f36150C1EFf0eB76276f6B7": {
      "symbol": "WAD",
      "decimals": 6,
      "isToken": true
    }
  }
}
```

### Schema (for other networks)

| Field                   | Type   | Description                                                          |
| ----------------------- | ------ | -------------------------------------------------------------------- |
| `chainId`               | number | EVM chain ID                                                         |
| `name`                  | string | Network display name                                                 |
| `rpcUrl`                | string | Public RPC endpoint                                                  |
| `blockExplorer`         | string | Explorer base URL                                                    |
| `contracts.lendingPool` | string | LendingPoolV2 address                                                |
| `contracts.oracle`      | string | Oracle (MockOracle or Chainlink adapter) address                     |
| `tokens`                | object | Map of token address → `{ symbol, decimals }` for configured markets |

### TypeScript example

```ts
// src/config/networks.ts
export type NetworkConfig = {
  chainId: number;
  name: string;
  rpcUrl: string;
  blockExplorer: string;
  contracts: {
    lendingPool: `0x${string}`;
    oracle: `0x${string}`;
  };
  tokens: Record<string, { symbol: string; decimals: number }>;
};

export const baseSepolia: NetworkConfig = {
  chainId: 84532,
  name: "Base Sepolia",
  rpcUrl: "https://sepolia.base.org",
  blockExplorer: "https://sepolia.basescan.org",
  contracts: {
    lendingPool: "0x8045c02eCd91E8ff98BE8B49277730c0781D2215",
    oracle: "0x74F6246AF46d21D1bC68a57A5934A42BB4F8EBdD",
    stoken: "0xC6eAc98D9135757E7f36150C1EFf0eB76276f6B7",
  },
  tokens: {
    "0xEC39F43632c681aebAdcab6C1c828bE8Fe723D7F": {
      symbol: "USDC",
      decimals: 6,
    },
    "0x5B39E3Ac93007e0F784E13C82AD8a4591B4c4545": {
      symbol: "cbBTC",
      decimals: 8,
    },
    "0xa9bDDa6528992e962e57D32eE0CAF493b526b0C2": {
      symbol: "EURC",
      decimals: 6,
    },
    "0xC6eAc98D9135757E7f36150C1EFf0eB76276f6B7": {
      symbol: "WAD",
      decimals: 6,
      isToken: true,
    },
  },
};

export const networks: Record<number, NetworkConfig> = {
  [baseSepolia.chainId]: baseSepolia,
};
```

---

## 8) Configuration Summary

| Variable       | Value                                            |
| -------------- | ------------------------------------------------ |
| RPC            | `https://sepolia.base.org`                       |
| Chain ID       | 84532                                            |
| Script         | `script/LendingPoolV2.s.sol:LendingPoolV2Script` |
| Gas (estimate) | ~0.000006 ETH                                    |

---

## 9) Troubleshooting

| Issue                                               | Solution                                                                         |
| --------------------------------------------------- | -------------------------------------------------------------------------------- |
| **"You seem to be using Foundry's default sender"** | Set `PRIVATE_KEY` env var or pass `--private-key`                                |
| **`Unauthorized()` on createMarket**                | Run the config script with the same `--private-key` as the deployer (pool owner) |
| **Insufficient funds**                              | Request Base Sepolia ETH from a faucet                                           |
| **Wrong network**                                   | Ensure `--chain-id 84532` and RPC point to Base Sepolia                          |
| **Verification fails**                              | Check `BASESCAN_API_KEY`; retry after deployment                                 |

---

_Document version: 1.0 | Target: Base Sepolia testnet | Date: Feb 2025_
