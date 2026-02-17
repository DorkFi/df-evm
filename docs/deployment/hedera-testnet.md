# Hedera Testnet Deployment

This document describes how to deploy DorkFi **LendingPoolV2Hedera** and MockOracle to **Hedera Testnet**. Hedera uses a dedicated pool contract (`LendingPoolV2Hedera`) that extends `LendingPoolV2` with chain-specific logic; deployment uses the Hedera script and HBAR for gas.

---

## 1) Prerequisites

### Network

| Property     | Value |
| ------------ | ----- |
| **Chain ID** | 296   |
| **RPC URL**  | `https://testnet.hashio.io/api` (or `https://296.rpc.thirdweb.com`) |
| **Explorer** | [hashscan.io/testnet](https://hashscan.io/testnet) |

### Deployer

- **Wallet**: EVM-compatible wallet (e.g. MetaMask) — use the same format as other EVM chains.
- **Gas token**: **HBAR** (Hedera native token). Deployment consumes a small amount of HBAR.
- **Private key**: Set `PRIVATE_KEY` for the deployer (or pass `--private-key`).

### Faucet (Testnet HBAR)

| Faucet        | URL |
| ------------- | --- |
| Hedera Portal | [portal.hedera.com/faucet](https://portal.hedera.com/faucet) — up to 100 testnet HBAR per 24h (account ID or EVM address). |
| Playground    | [portal.hedera.com/playground](https://portal.hedera.com/playground) — new testnet accounts can start with 1,000 testnet HBAR. |

First-time EVM address use on the faucet triggers auto account creation on Hedera for that address.

---

## 2) Deploy & Setup (Quick Start)

**Prerequisites:** `.env` with `PRIVATE_KEY=0x...` and testnet HBAR in the deployer wallet.

```bash
source .env

# Deploy (MockOracle, LendingPoolV2Hedera, ATokens, SToken, markets, oracle prices)
forge script script/LendingPoolV2Hedera.s.sol:LendingPoolV2HederaScript \
  --rpc-url https://296.rpc.thirdweb.com \
  --broadcast \
  --chain-id 296 \
  --private-key $PRIVATE_KEY
```

The script deploys **LendingPoolV2Hedera** (not the base LendingPoolV2), plus MockOracle, ATokens (USDC, cbBTC, EURC), SToken (WAD), and creates markets. No separate config script is required for the single-script flow.

---

## 3) Deploy Core Contracts (Manual)

### Build

```bash
forge build
```

### Deploy

```bash
export PRIVATE_KEY=0x...   # your deployer private key

forge script script/LendingPoolV2Hedera.s.sol:LendingPoolV2HederaScript \
  --rpc-url https://testnet.hashio.io/api \
  --broadcast \
  --chain-id 296
```

### Deployed Contracts

| Contract               | Description                                                                 |
| ---------------------- | --------------------------------------------------------------------------- |
| **MockOracle**         | Mock price oracle; returns `setPrice` values or defaults to $1               |
| **LendingPoolV2Hedera** | Hedera-specific lending pool (extends LendingPoolV2); add HTS/hooks here   |
| **AToken** (x3)        | USDC, cbBTC, EURC (deployed by script)                                      |
| **SToken** (WAD)       | Borrow-only market token (deployed by script)                              |

Deployment order: MockOracle → LendingPoolV2Hedera → ATokens → create markets → SToken → set oracle prices and limits.

**Hedera-specific code:** All chain-specific logic (e.g. HTS token association, Hedera native service calls) belongs in `src/LendingPoolV2Hedera.sol`. To override token transfer or price-feed payment behavior, the corresponding functions in `LendingPoolV2.sol` (`_pull`, `_push`, `_ensurePaymentForFetchPriceFeed`) would need to be marked `virtual` so that `LendingPoolV2Hedera` can override them.

---

## 4) Verification on HashScan

Foundry’s built-in `--verify` targets Etherscan-like APIs. Hedera uses **HashScan** and may require their verification process instead.

- **Option A**: Try Foundry verification if an Etherscan-compatible API for Hedera/HashScan exists (check [Foundry book](https://book.getfoundry.sh/forge/verifying) and [Hedera docs](https://docs.hedera.com/hedera/tutorials/smart-contracts/how-to-verify-a-smart-contract-on-hashscan)).
- **Option B**: Verify manually on [HashScan Testnet](https://hashscan.io/testnet) using their “Verify contract” flow (upload source, compiler settings, and constructor args).

---

## 5) Post-Deployment

- **Markets**: The single-script flow already creates markets and sets oracle prices. If you deploy without the full script, create markets via `pool.createMarket(token, params)` and set prices with `oracle.setPrice(marketId, price)` (8 decimals).
- **Tokens**: On Hedera testnet there are no canonical “Base Sepolia USDC/cbBTC/EURC” addresses; the script deploys its own ATokens and SToken, so you don’t need existing token addresses.

---

## 6) UI Config

Use the same schema as Base Sepolia; point to Hedera testnet and your deployed addresses.

### JSON (example)

```json
{
  "chainId": 296,
  "name": "Hedera Testnet",
  "rpcUrl": "https://testnet.hashio.io/api",
  "blockExplorer": "https://hashscan.io/testnet",
  "contracts": {
    "lendingPool": "<LENDING_POOL_ADDRESS>",
    "oracle": "<ORACLE_ADDRESS>",
    "stoken": "<STOKEN_ADDRESS>"
  },
  "tokens": {}
}
```

Fill `contracts` and `tokens` from your deploy script output and any tokens you add later.

---

## 7) Configuration Summary

| Variable | Value |
| -------- | ----- |
| RPC      | `https://testnet.hashio.io/api` |
| Chain ID | 296 |
| Script   | `script/LendingPoolV2Hedera.s.sol:LendingPoolV2HederaScript` |
| Pool contract | `src/LendingPoolV2Hedera.sol` (Hedera-specific logic lives here) |
| Gas      | HBAR (fund via [portal.hedera.com/faucet](https://portal.hedera.com/faucet)) |

---

## 8) Troubleshooting

| Issue | Solution |
| ----- | -------- |
| **"You seem to be using Foundry's default sender"** | Set `PRIVATE_KEY` or pass `--private-key` |
| **Insufficient funds** | Request testnet HBAR from [portal.hedera.com/faucet](https://portal.hedera.com/faucet) |
| **Wrong network** | Use `--chain-id 296` and RPC `https://testnet.hashio.io/api` |
| **RPC timeouts** | Try alternate RPC: `https://296.rpc.thirdweb.com` |
| **`Unauthorized()` on createMarket** | Run config with the same private key as the deployer (pool owner) |
| **Many txs fail with "Transaction Failure" / Paid: 0 ETH** | Often **gas price below base fee**. Use `--slow` and a higher gas price (see below). |
| **"gas price is less than basefee"** (when replaying) | Hedera’s base fee can move; broadcast with an explicit higher gas price. |

### If most transactions fail (only first 1–2 succeed)

Hedera testnet can reject later transactions in a batch when:

1. **Gas price below base fee** – The RPC may return a lower gas price than the next block’s base fee, so later txs get rejected (they show as failed with 0 gas used).
2. **Too many txs sent at once** – Nonce/ordering can get messy when many txs are in the mempool.

**Recommended deploy command:**

```bash
source .env

forge script script/LendingPoolV2Hedera.s.sol:LendingPoolV2HederaScript \
  --rpc-url https://296.rpc.thirdweb.com \
  --broadcast \
  --chain-id 296 \
  --private-key $PRIVATE_KEY \
  --slow \
  --with-gas-price 880000000000
```

- **`--slow`** – Sends one transaction at a time and waits for confirmation before the next. More reliable on Hedera.
- **`--with-gas-price 880000000000`** – Hedera testnet RPCs often enforce a **minimum of 880 gwei**. Use at least this; if you see "below configured minimum gas price", use the value from the error message or slightly higher (e.g. `900000000000`).

Alternative RPC if thirdweb is flaky: `--rpc-url https://testnet.hashio.io/api`

---

_Document version: 1.0 | Target: Hedera Testnet | Date: Feb 2025_
