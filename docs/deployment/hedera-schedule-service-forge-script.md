# Hedera Schedule Service and Forge Script

The Hedera keeper runs periodic work (e.g. interest accrual) by rescheduling itself via Hedera’s native Schedule Service at `0x16B`, so no off-chain bot is needed. When starting that keeper from a Foundry script, **`forge script` fails with "call to non-contract address 0x16B"** even when using `--skip-simulation`—and the revert happens before any transaction is sent. This document explains why that happens and the recommended fix.

---

## The problem

The keeper on **LendingPoolV2Hedera** uses Hedera’s [Schedule Service](https://docs.hedera.com/hedera/core-concepts/smart-contracts/system-smart-contracts/hedera-schedule-service) (HIP-1215). The Schedule Service is a **system precompile** at address `0x16B`. Contract code calls it for:

- `hasScheduleCapacity(expirySecond, gasLimit)` — to check if a given second has capacity before scheduling
- `scheduleCall(to, expirySecond, gasLimit, value, callData)` — to create the next scheduled run

When starting the keeper via a Forge script that calls `pool.startKeeper(marketId, intervalSeconds)`, the script fails with:

```
Error: script failed: call to non-contract address 0x000000000000000000000000000000000000016B
```

The trace shows the revert happening when the pool calls `hasScheduleCapacity(...)` on `0x16B`. This occurs even when:

- You use the same RPC as other Hedera tooling (e.g. `https://testnet.hashio.io/api`).
- You pass **`--skip-simulation`**.
- The [tutorial-hss-rebalancer](https://github.com/hashgraph/hedera-smart-contracts/tree/main/tutorials/tutorial-hss-rebalancer-capacity-aware) works on the same network with the same Schedule Service pattern.

So the confusion is: *why does the tutorial work but Forge script fail?*

---

## Why it happens

The difference is **where** the contract code runs.

1. **Tutorial (Hardhat / Ethers)**  
   You call `rebalancer.startRebalancing(intervalSeconds)`. Hardhat builds the transaction and **sends it to the RPC**. The contract executes **on Hedera**. On Hedera, the precompile at `0x16B` exists, so the call succeeds.

2. **Forge script**  
   When you run `forge script ... --broadcast` (with or without `--skip-simulation`), Forge must first decide **what transactions** to broadcast. To do that, it **runs the script in the local Foundry VM**. That VM is a standard EVM: it does **not** include Hedera system contracts. So when the script calls the pool and the pool calls `hasScheduleCapacity` → `0x16B`, the local VM has no contract at `0x16B` and the call reverts with “call to non-contract address 0x16B”. The revert happens **before** any transaction is sent to Hedera.

In other words: **`--skip-simulation` does not skip running the script in the local VM to build the broadcast list.** It only skips a separate “on-chain simulation” step. The script still executes locally, so any code path that touches `0x16B` will revert in Foundry’s VM.

---

## The fix: send the transaction directly

Avoid running the keeper-start logic inside a Forge script. Send the `startKeeper` call as a single transaction so that the **only** execution is on Hedera, where `0x16B` exists.

**Use `cast send`** (from [Foundry](https://getfoundry.sh)):

```bash
source .env

# Default: market id 0, interval 3600 seconds
cast send $LENDING_POOL_ADDRESS "startKeeper(uint64,uint256)" 0 3600 \
  --rpc-url https://testnet.hashio.io/api \
  --chain-id 296 \
  --private-key $PRIVATE_KEY
```

With optional env vars (e.g. `MARKET_ID`, `KEEPER_INTERVAL_SECONDS`):

```bash
cast send $LENDING_POOL_ADDRESS "startKeeper(uint64,uint256)" \
  "${MARKET_ID:-0}" "${KEEPER_INTERVAL_SECONDS:-3600}" \
  --rpc-url https://testnet.hashio.io/api \
  --chain-id 296 \
  --private-key $PRIVATE_KEY
```

**Market IDs** (for reference): `0` = USDC, `1` = cbBTC, `2` = EURC, `3` = WAD.

No script runs in the local VM; the transaction is sent to Hedera and executed there, so the Schedule Service precompile is available and the keeper starts as intended.

---

## Summary

| Approach | Where contract runs | Result |
|----------|---------------------|--------|
| Hardhat / Ethers (`contract.startKeeper(...)`) | On Hedera only | ✅ Works |
| `forge script` (even with `--skip-simulation`) | Script runs in local VM → hits 0x16B → reverts | ❌ Fails |
| `cast send` with `startKeeper(uint64,uint256)` | On Hedera only | ✅ Works |

For starting the Hedera keeper, use **`cast send`** (or another flow that sends the tx without simulating the contract in Foundry’s VM). See [Hedera Keeper Lifecycle](./hedera-keeper-lifecycle.md) for full keeper lifecycle and options.
