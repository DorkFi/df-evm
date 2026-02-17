# 0G (OG) Testnet Deployment

This document describes how to deploy DorkFi **LendingPoolV2** and MockOracle to **0G Testnet** (0G-Testnet-Galileo). The same base pool contract as Base Sepolia is used; deployment uses the 0G script and OG for gas.

---

## 1) Prerequisites

### Network

| Property     | Value |
| ------------ | ----- |
| **Chain ID** | 16602 |
| **RPC URL**  | `https://evmrpc-testnet.0g.ai` |
| **Explorer** | [chainscan-galileo.0g.ai](https://chainscan-galileo.0g.ai) |

### Deployer

- **Wallet**: EVM-compatible wallet (e.g. MetaMask).
- **Gas token**: **OG** (0G native token). Deployment consumes a small amount of OG.
- **Private key**: Set `PRIVATE_KEY` for the deployer (or pass `--private-key`).

### Faucet (Testnet OG)

| Faucet   | URL |
| -------- | --- |
| 0G       | [faucet.0g.ai](https://faucet.0g.ai) — up to 0.1 OG per day per address. |
| Hub      | [hub.0g.ai/faucet](https://hub.0g.ai/faucet) — alternative faucet. |

---

## 2) Deploy & Setup (Quick Start)

**Prerequisites:** `.env` with `PRIVATE_KEY=0x...` and testnet OG in the deployer wallet.

```bash
source .env

# Deploy (MockOracle, LendingPoolV2, ATokens, SToken, markets, oracle prices)
# 0G testnet uses EIP-1559; set both max fee and priority fee so priority <= max (e.g. both 2 gwei).
forge script script/LendingPoolV2OG.s.sol:LendingPoolV2OGScript \
  --rpc-url https://evmrpc-testnet.0g.ai \
  --broadcast \
  --chain-id 16602 \
  --private-key $PRIVATE_KEY \
  --with-gas-price 2000000000 \
  --priority-gas-price 2000000000
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

forge script script/LendingPoolV2OG.s.sol:LendingPoolV2OGScript \
  --rpc-url https://evmrpc-testnet.0g.ai \
  --broadcast \
  --chain-id 16602 \
  --with-gas-price 2000000000 \
  --priority-gas-price 2000000000
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

Use Foundry’s `--verify` with an Etherscan-compatible block explorer for 0G testnet if available, or verify manually on [chainscan-galileo.0g.ai](https://chainscan-galileo.0g.ai) (upload source, compiler settings, and constructor args).

---

## 5) Post-Deployment

- **Markets**: The script already creates markets and sets oracle prices. To add more, use `pool.createMarket(token, params)` and `oracle.setPrice(marketId, price)` (8 decimals).
- **Tokens**: The script deploys its own ATokens and SToken; no pre-existing token addresses are required.

---

## 6) UI Config

Use the same schema as Base Sepolia; point to 0G testnet and your deployed addresses.

### JSON (example)

```json
{
  "chainId": 16602,
  "name": "0G Testnet",
  "rpcUrl": "https://evmrpc-testnet.0g.ai",
  "blockExplorer": "https://chainscan-galileo.0g.ai",
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
| RPC      | `https://evmrpc-testnet.0g.ai` |
| Chain ID | 16602 |
| Script   | `script/LendingPoolV2OG.s.sol:LendingPoolV2OGScript` |
| Pool contract | `src/LendingPoolV2.sol` |
| Gas      | OG (fund via [faucet.0g.ai](https://faucet.0g.ai)) |

---

## 8) Troubleshooting

| Issue | Solution |
| ----- | -------- |
| **"You seem to be using Foundry's default sender"** | Set `PRIVATE_KEY` or pass `--private-key` |
| **Insufficient funds** | Request testnet OG from [faucet.0g.ai](https://faucet.0g.ai) (0.1 OG/day; more via [0G Discord](https://discord.com/invite/0glabs)) |
| **Wrong network** | Use `--chain-id 16602` and RPC `https://evmrpc-testnet.0g.ai` |
| **`Unauthorized()` on createMarket** | Run with the same private key as the deployer (pool owner) |
| **"transaction gas price below minimum: gas tip cap 1, minimum needed 2000000000"** | 0G testnet enforces a minimum gas price. Use `--with-gas-price 2000000000` and `--priority-gas-price 2000000000`. |
| **"max priority fee per gas higher than max fee per gas"** | EIP-1559 requires priority ≤ max. Set both explicitly: `--with-gas-price 2000000000 --priority-gas-price 2000000000`. |

### If transactions fail (gas price or priority > max)

Use explicit max fee and priority fee so that **priority ≤ max** and both meet the chain minimum (2 gwei):

```bash
source .env

forge script script/LendingPoolV2OG.s.sol:LendingPoolV2OGScript \
  --rpc-url https://evmrpc-testnet.0g.ai \
  --broadcast \
  --chain-id 16602 \
  --private-key $PRIVATE_KEY \
  --with-gas-price 2000000000 \
  --priority-gas-price 2000000000
```

If the RPC reports a higher minimum later, use that value for both (e.g. `3000000000`).

---

_Document version: 1.0 | Target: 0G Testnet (Galileo) | Date: Feb 2025_
