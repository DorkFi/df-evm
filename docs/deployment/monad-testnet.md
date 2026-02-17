# Monad Testnet Deployment

This document describes how to deploy DorkFi **LendingPoolV2** and MockOracle to **Monad Testnet**. The same base pool contract as Base Sepolia is used; deployment uses the Monad script and MON for gas.

---

## 1) Prerequisites

### Network

| Property     | Value |
| ------------ | ----- |
| **Chain ID** | 10143 |
| **RPC URL**  | `https://testnet-rpc.monad.xyz` (or `https://rpc.ankr.com/monad_testnet`) |
| **Explorer** | [testnet.monadvision.com](https://testnet.monadvision.com) |

### Deployer

- **Wallet**: EVM-compatible wallet (e.g. MetaMask).
- **Gas token**: **MON** (Monad native token). Deployment consumes a small amount of MON.
- **Private key**: Set `PRIVATE_KEY` for the deployer (or pass `--private-key`).

### Faucet (Testnet MON)

| Faucet   | URL |
| -------- | --- |
| Monad    | [faucet.monad.xyz](https://faucet.monad.xyz) — request testnet MON for your address. |

---

## 2) Deploy & Setup (Quick Start)

**Prerequisites:** `.env` with `PRIVATE_KEY=0x...` and testnet MON in the deployer wallet.

```bash
source .env

# Deploy (MockOracle, LendingPoolV2, ATokens, SToken, markets, oracle prices)
forge script script/LendingPoolV2Monad.s.sol:LendingPoolV2MonadScript \
  --rpc-url https://testnet-rpc.monad.xyz \
  --broadcast \
  --chain-id 10143 \
  --private-key $PRIVATE_KEY
```

The script deploys **LendingPoolV2**, MockOracle, ATokens (USDC, cbBTC, EURC), SToken (WAD), and creates markets.

---

## 3) Deploy Core Contracts (Manual)

### Build

```bash
forge build
```

### Deploy

```bash
export PRIVATE_KEY=0x...   # your deployer private key

forge script script/LendingPoolV2Monad.s.sol:LendingPoolV2MonadScript \
  --rpc-url https://testnet-rpc.monad.xyz \
  --broadcast \
  --chain-id 10143
```

### Deployed Contracts

| Contract       | Description                                                         |
| -------------- | ------------------------------------------------------------------- |
| **MockOracle** | Mock price oracle; returns `setPrice` values or defaults to $1      |
| **LendingPoolV2** | Lending pool (same as Base Sepolia)                             |
| **AToken** (x3) | USDC, cbBTC, EURC (deployed by script)                             |
| **SToken** (WAD) | Borrow-only market token (deployed by script)                     |

Deployment order: MockOracle → LendingPoolV2 → ATokens → create markets → SToken → set oracle prices and limits.

---

## 4) Verification

Use Foundry’s `--verify` with an Etherscan-compatible block explorer for Monad testnet if available, or verify manually on [testnet.monadvision.com](https://testnet.monadvision.com) (upload source, compiler settings, and constructor args).

---

## 5) Post-Deployment

- **Markets**: The script already creates markets and sets oracle prices. To add more, use `pool.createMarket(token, params)` and `oracle.setPrice(marketId, price)` (8 decimals).
- **Tokens**: The script deploys its own ATokens and SToken; no pre-existing token addresses are required.

---

## 6) UI Config

Use the same schema as Base Sepolia; point to Monad testnet and your deployed addresses.

### JSON (example)

```json
{
  "chainId": 10143,
  "name": "Monad Testnet",
  "rpcUrl": "https://testnet-rpc.monad.xyz",
  "blockExplorer": "https://testnet.monadvision.com",
  "contracts": {
    "lendingPool": "<LENDING_POOL_ADDRESS>",
    "oracle": "<ORACLE_ADDRESS>",
    "stoken": "<STOKEN_ADDRESS>"
  },
  "tokens": {}
}
```

Fill `contracts` and `tokens` from your deploy script output.

---

## 7) Configuration Summary

| Variable | Value |
| -------- | ----- |
| RPC      | `https://testnet-rpc.monad.xyz` |
| Chain ID | 10143 |
| Script   | `script/LendingPoolV2Monad.s.sol:LendingPoolV2MonadScript` |
| Pool contract | `src/LendingPoolV2.sol` |
| Gas      | MON (fund via [faucet.monad.xyz](https://faucet.monad.xyz)) |

---

## 8) Troubleshooting

| Issue | Solution |
| ----- | ----- |
| **"You seem to be using Foundry's default sender"** | Set `PRIVATE_KEY` or pass `--private-key` |
| **Insufficient funds** | Request testnet MON from [faucet.monad.xyz](https://faucet.monad.xyz) |
| **Wrong network** | Use `--chain-id 10143` and RPC `https://testnet-rpc.monad.xyz` |
| **RPC timeouts** | Try alternate RPC: `https://rpc.ankr.com/monad_testnet` |
| **`Unauthorized()` on createMarket** | Run with the same private key as the deployer (pool owner) |

---

_Document version: 1.0 | Target: Monad Testnet | Date: Feb 2025_
