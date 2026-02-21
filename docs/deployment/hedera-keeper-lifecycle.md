# Hedera Keeper Lifecycle

This document describes the **keeper** lifecycle for **LendingPoolV2Hedera** on Hedera. The keeper uses Hedera’s native [Schedule Service](https://github.com/hashgraph/hedera-smart-contracts/tree/main/contracts/system-contracts/hedera-schedule-service) to run periodic work (e.g. interest accrual or maintenance) at fixed intervals without an external bot.

---

## 1) Overview

| Concept              | Description                                                                                                                                                                                                                               |
| -------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Keeper**           | A scheduled contract call that runs at a fixed interval. Each **market** has its own keeper config; multiple markets can have keepers running at different intervals.                                                                     |
| **Schedule Service** | Hedera system contract (HRC-1215) that executes a contract call at a given consensus **second**. The pool uses `scheduleCall(to, expirySecond, gasLimit, value, callData)` so the next run is executed by the network at the chosen time. |
| **Loop**             | Each execution calls `runKeeper(marketId)`, which updates state and schedules the _next_ run at `lastCallTime + intervalSeconds` (with capacity/jitter if needed).                                                                        |

The contract does not use an external keeper bot; the next execution is created as a Hedera scheduled transaction from within the previous execution.

---

## 2) Lifecycle

### Start

**Function:** `startKeeper(uint64 marketId, uint256 intervalSeconds)`

To start the keeper on an **existing** LendingPoolV2Hedera deployment, send the call **directly** so it runs on Hedera (where the Schedule Service precompile at 0x16B exists). Do **not** use `forge script` for this: even with `--skip-simulation`, Forge still runs the script in the local VM to build the broadcast list, and the local VM has no 0x16B, so the script reverts before any transaction is sent. For a full explanation of this behavior and the fix, see [Hedera Schedule Service and Forge Script](hedera-schedule-service-forge-script.md).

**Recommended: use `cast send`**

```bash
source .env
# Default: market 0, interval 3600
cast send $LENDING_POOL_ADDRESS "startKeeper(uint64,uint256)" 0 3600 \
  --rpc-url https://testnet.hashio.io/api --chain-id 296 --private-key $PRIVATE_KEY
```

With optional env (e.g. `MARKET_ID=0`, `KEEPER_INTERVAL_SECONDS=3600`):

```bash
cast send $LENDING_POOL_ADDRESS "startKeeper(uint64,uint256)" ${MARKET_ID:-0} ${KEEPER_INTERVAL_SECONDS:-3600} \
  --rpc-url https://testnet.hashio.io/api --chain-id 296 --private-key $PRIVATE_KEY
```

- **Who:** Any caller (no access control in current implementation).
- **When:** Call once per market when you want the keeper to begin.
- **Checks:** `intervalSeconds > 0`, keeper for this market not already active.
- **Effect:**
  - Sets `keeperConfigs[marketId]`: `active = true`, `intervalSeconds`, `lastCallTime = block.timestamp`, `callCount = 0`.
  - Schedules the first execution at `block.timestamp + intervalSeconds` (or nearest second with capacity; see below).
  - Emits `KeeperStarted(intervalSeconds, firstScheduledAt)`.

After this, the first run happens at the scheduled consensus second; that run then schedules the next, and so on.

### Execution loop

**Function:** `runKeeper(uint64 marketId)` (called by the Schedule Service at the scheduled time)

- **Who:** Invoked by Hedera when the scheduled transaction executes (the scheduled call targets the pool with `runKeeper(marketId)`).
- **When:** At the consensus second that was chosen when the schedule was created.
- **Checks:** `keeperConfigs[marketId].active` must be true.
- **Effect:**
  - Increments `callCount`, updates `lastCallTime = block.timestamp`.
  - Emits `KeeperExecuted(timestamp, callCount)`.
  - Schedules the _next_ run at `block.timestamp + intervalSeconds` (again with capacity/jitter).
  - Stores `lastScheduleAddress` and emits `KeeperScheduled(chosenTime, desiredTime, scheduleAddress)`.

So the lifecycle is: **startKeeper** → first **runKeeper** (by schedule) → **runKeeper** (by schedule) → … ad infinitum until the keeper is stopped or the schedule is deleted.

### Stopping

- The contract emits `KeeperStopped` but does **not** currently expose a `stopKeeper` function.
- Hedera’s Schedule Service provides **`deleteSchedule(scheduleAddress)`**; the pool inherits this via `HederaScheduleService` but does not call it from a public API.
- To stop a keeper today:
  - **Option A:** Add a `stopKeeper(marketId)` that sets `active = false` and calls `deleteSchedule(keeperConfigs[marketId].lastScheduleAddress)` so the next run is never scheduled (and the current pending schedule is cancelled).
  - **Option B:** Use any Hedera API that can delete a schedule by the schedule’s address (`lastScheduleAddress`). After the current schedule executes once more, set `active = false` in a separate transaction if the contract later supports it, or accept that one more run may occur before the chain has no further schedule for this market.

Until `stopKeeper` exists, the keeper runs indefinitely once started; deleting the latest schedule only prevents the _next_ run from being scheduled if done before that run executes.

---

## 3) Configuration and state

Defined in `LendingPoolV2Hedera.sol`:

| Constant / storage            | Value / meaning                                                                    |
| ----------------------------- | ---------------------------------------------------------------------------------- |
| **KEEPER_GAS_LIMIT**          | `2_000_000` — gas limit for each scheduled `runKeeper` call.                       |
| **KeeperConfig** (per market) | `active`, `intervalSeconds`, `lastCallTime`, `callCount`, `lastScheduleAddress`.   |
| **keeperConfigs(marketId)**   | One config per market; multiple markets can have keepers with different intervals. |

### Events

| Event                                                         | When                                                              |
| ------------------------------------------------------------- | ----------------------------------------------------------------- |
| **KeeperStarted**(intervalSeconds, firstScheduledAt)          | After `startKeeper` schedules the first run.                      |
| **KeeperScheduled**(chosenTime, desiredTime, scheduleAddress) | After each schedule creation (from `startKeeper` or `runKeeper`). |
| **KeeperExecuted**(timestamp, count)                          | After each `runKeeper` execution.                                 |
| **KeeperStopped**                                             | Reserved; no function currently emits it.                         |

---

## 4) Hedera Schedule Service details

### Scheduling

- **`scheduleCall(to, expirySecond, gasLimit, value, callData)`** — Creates a scheduled transaction that runs at consensus time `expirySecond` (Unix second). The pool passes `address(this)`, the chosen second, `KEEPER_GAS_LIMIT`, `0` value, and `abi.encodeWithSelector(this.runKeeper.selector, marketId)`.
- **Capacity:** Hedera limits how much scheduled work can be in a given consensus second. The pool uses **`hasScheduleCapacity(expirySecond, gasLimit)`** before scheduling. If the desired second has no capacity, the pool uses **`_findAvailableSecond`** to pick a later second (with exponential backoff and PRNG jitter, up to 8 probes). So the actual run time may be slightly after `desiredTime`.

### Execution and payment

- The **scheduled transaction** is executed by the network at (or after) the chosen second. The **payer** for that transaction is the **contract** (the pool); the pool must hold enough **HBAR** to pay for the scheduled execution. Ensure the pool has a small HBAR balance for keeper runs.
- **`deleteSchedule(scheduleAddress)`** — Cancels a scheduled transaction. Not yet wired to a public `stopKeeper`; see [Stopping](#stopping) above.

### References

- [Hedera Schedule Service (hedera-smart-contracts)](https://github.com/hashgraph/hedera-smart-contracts/tree/main/contracts/system-contracts/hedera-schedule-service)
- HRC-1215 (schedule contract calls); HRC-755 (authorize/sign) if using payers other than the contract.

---

## 5) Operational notes

| Topic                     | Notes                                                                                                                                                                                                 |
| ------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Who can start**         | `startKeeper` has no access control; anyone can start a keeper for a market. Consider adding `onlyOwner` or a dedicated role if that should be restricted.                                            |
| **Pool HBAR balance**     | The pool is the payer for each scheduled `runKeeper`. Fund the pool with HBAR so scheduled transactions do not fail for insufficient funds.                                                           |
| **Market existence**      | The contract has a TODO to check that the market exists before starting a keeper; currently invalid `marketId` can be used and may revert in `_scheduleNextKeeperCall` or when the schedule executes. |
| **Gas limit**             | If `runKeeper` logic grows (e.g. accrual, liquidations), ensure `KEEPER_GAS_LIMIT` is sufficient or make it configurable.                                                                             |
| **Throttling / capacity** | If many keepers or other scheduled txs use the same second, `hasScheduleCapacity` may be false and the pool will reschedule to a later second; execution is then delayed by the backoff/jitter.       |

---

## 6) Summary

1. Call **`startKeeper(marketId, intervalSeconds)`** once per market to start the keeper.
2. Hedera runs **`runKeeper(marketId)`** at the scheduled time; the pool then schedules the next run.
3. Keep the **pool funded with HBAR** for scheduled execution.
4. There is no in-contract **stop** yet; use **`deleteSchedule(lastScheduleAddress)`** (e.g. via a future `stopKeeper`) or Hedera APIs to cancel the next run; add `stopKeeper` to set `active = false` and cancel the pending schedule for a clean stop.

---

_Document version: 1.0 | Target: LendingPoolV2Hedera on Hedera | Date: Feb 2025_
