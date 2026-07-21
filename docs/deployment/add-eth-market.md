# Add ETH Market (Existing Deployments)

Adds a mintable **ETH AToken** market to an already-deployed `LendingPoolV2` + `MockOracle` pair. Same pattern as USDC/cbBTC/EURC test tokens.

---

## Prerequisites

| Requirement | Notes |
|-------------|--------|
| **Pool owner key** | Same `PRIVATE_KEY` used for the original deploy |
| **Testnet gas** | ETH (Base Sepolia), HBAR (Hedera), MON (Monad) |
| **Foundry** | `forge build` from `df-evm` root |
| **`.env`** | `PRIVATE_KEY=0x...` |

Verify owner matches:

```bash
cast call <LENDING_POOL_ADDRESS> "owner()(address)" --rpc-url <RPC>
cast wallet address $PRIVATE_KEY
```

---

## 1) Run AddEthMarket script

Set pool + oracle for your network, then broadcast.

### Base Sepolia

```bash
source .env
LENDING_POOL_ADDRESS=0x8045c02eCd91E8ff98BE8B49277730c0781D2215 \
ORACLE_ADDRESS=0x74F6246AF46d21D1bC68a57A5934A42BB4F8EBdD \
FOUNDRY_PROFILE=base-sepolia forge script script/AddEthMarket.s.sol:AddEthMarketScript \
  --rpc-url base_sepolia --broadcast \
  --private-key $PRIVATE_KEY --sender $(cast wallet address $PRIVATE_KEY)
```

### Hedera Testnet

```bash
source .env
LENDING_POOL_ADDRESS=0xBffF7E4c4d42B22e4F56bd2c013cb26311DD80d2 \
ORACLE_ADDRESS=0x260733458C7e18BF82965d11168196C3F6227566 \
FOUNDRY_PROFILE=hedera-testnet forge script script/AddEthMarket.s.sol:AddEthMarketScript \
  --rpc-url hedera_testnet --broadcast \
  --private-key $PRIVATE_KEY --sender $(cast wallet address $PRIVATE_KEY)
```

### Monad Testnet

```bash
source .env
LENDING_POOL_ADDRESS=0x7DF57FcBe3796BC3950DF8bb2528D7F2e1A02EEd \
ORACLE_ADDRESS=0x14d85F95C34E3dB283Fa81EBA6608bAda838f9fA \
FOUNDRY_PROFILE=monad-testnet forge script script/AddEthMarket.s.sol:AddEthMarketScript \
  --rpc-url monad_testnet --broadcast \
  --private-key $PRIVATE_KEY --sender $(cast wallet address $PRIVATE_KEY)
```

### Optional: custom oracle price

Price uses 8 decimals (`1e8` = $1). Default is `3000e8` ($3000):

```bash
ETH_PRICE_USD=350000000000 ... forge script script/AddEthMarket.s.sol:AddEthMarketScript ...
```

---

## 2) Dry run (no broadcast)

Omit `--broadcast` to simulate. Useful to confirm the signer is the pool owner before spending gas.

---

## 3) Update UI (`base-bl-ui`)

Copy `AToken_ETH` from script output into `src/config/chains.ts` for the matching network:

**`contracts.atokens`:**

```ts
eth: "0x<AToken_ETH>",
```

**`tokens`:**

```ts
"0x<AToken_ETH>": { symbol: "ETH", decimals: 18 },
```

Each network gets a **different** AToken address (one deploy per chain).

---

## 4) Verify

1. **Markets page** — ETH row shows **Active** (not Pending)
2. **Gas Station** — ETH appears in mint dropdown
3. **Oracle page** — ETH price listed (~$3000 default)
4. **Debug page** — `marketIdByToken` for ETH token returns a valid ID

---

## What the script does

1. Deploy `AToken("Ether", "ETH", 18, 0)` — permissionless `mint()` for testnet
2. `pool.createMarket(ethToken, params)` — owner only
3. `oracle.setPrice(marketId, 3000e8)` — anyone on MockOracle
4. `setMaxTotalDeposits/Borrows(marketId, max)` — owner only

---

## Fresh deploys

New full deploys via `LendingPoolV2*.s.sol` / `Deploy.s.sol` include ETH automatically (via `LendingPoolV2DeployBase`).

---

## Troubleshooting

| Error | Fix |
|-------|-----|
| `Unauthorized()` | Signer is not pool owner — use original deployer key |
| `TokenAlreadyHasMarket()` | ETH market already exists for that token |
| Default sender error | Set `PRIVATE_KEY` in `.env` and pass `--private-key` + `--sender` |
