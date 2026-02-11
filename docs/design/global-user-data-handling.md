# Global User Data Handling

This document describes how the protocol aggregates and maintains user positions across all markets through `GlobalUserData`. Global user data is the cross-market view of a user's collateral and borrow values, used for health factor calculation, borrow capacity checks, and liquidation eligibility.

## Overview

Each user has two layers of position data:

| Layer | Storage | Scope | Purpose |
|-------|---------|-------|---------|
| **Per-market (UserData)** | `users[Bytes40(user+market)]` | Single market | Scaled deposits/borrows, indices, last price |
| **Global (GlobalUserData)** | `global_users[Account]` | All markets | Total collateral value, total borrow value (USD) |

`GlobalUserData` aggregates per-market positions into USD-denominated totals. These totals drive health factor, collateral factor checks, and liquidation eligibility.

## Data Structure

```python
class GlobalUserData(arc4.Struct):
    total_collateral_value: arc4.UInt256  # Sum of collateral value across markets (USD, SCALE)
    total_borrow_value: arc4.UInt256      # Sum of borrow value across markets (USD, SCALE)
    last_update_time: arc4.UInt64         # Last time global values were updated
```

- Values use `SCALE` (10^18) for precision.
- `total_collateral_value` = sum of (deposit_amount × price) for each market where the user has deposits.
- `total_borrow_value` = sum of (borrow_amount × price) for each market where the user has borrows.

## Storage and Defaults

- **Storage**: `global_users: BoxMap(Account, GlobalUserData)`
- **Default**: New users have no entry. `_get_global_user()` returns a default from `LendingPoolStorage.get_global_user_default()` (zeros) when the key is missing.
- **Persistence**: Entries are written only when the user has an active position. A user with no deposits or borrows may have no stored entry.

## Update Triggers

Global user data is updated in these cases:

### 1. Deposit / Withdraw

When a user deposits or withdraws, collateral changes:

- **Deposit**: `_increment_global_collateral(user_id, value)` adds the new collateral value.
- **Withdraw**: `_decrement_global_collateral(user_id, value)` subtracts the withdrawn collateral value.

`_update_user_market_collatera` → `_update_global_collateral` is used when the collateral value in a market changes (e.g., price change, interest accrual).

### 2. Borrow / Repay

When a user borrows or repays:

- **Borrow**: `_increment_global_borrows(user_id, value)` adds the new borrow value.
- **Repay**: `_decrement_global_borrows(user_id, value)` subtracts the repaid borrow value.

`_update_user_market_borrows` → `_update_global_borrows` is used when the borrow value in a market changes (e.g., price change, interest accrual).

### 3. Price Changes

When a market price changes, the USD value of collateral and borrows in that market changes. `_sync_user_market_for_price_change`:

1. Fetches the new price.
2. Calls `_update_user_global_values_for_price_change`, which:
   - Reads the user’s per-market data for that market.
   - Computes old and new values for collateral and borrows.
   - Calls `_update_global_collateral` and `_update_global_borrows` with the deltas.
3. Resolves any accumulated interest.

### 4. Interest Accrual

When interest is resolved:

- **Deposit interest**: `_resolve_accumulated_deposit_interest` → `_update_global_collateral(user_id, 0, interest_value)`.
- **Borrow interest**: `_resolve_accumulated_borrow_interest` → `_update_global_borrows(user_id, 0, interest_value)`.

## Update Model: Old/New Value Pattern

Global updates use an old/new value pattern to support deltas and avoid double-counting:

```python
def _update_global_collateral(user_id, old_value, new_value):
    global_user = _get_global_user(user_id)
    if old_value > global_user.total_collateral_value:
        # Safety: clamp if old_value exceeds stored (e.g. stale data)
        global_user.total_collateral_value = new_value
    else:
        global_user.total_collateral_value = (
            global_user.total_collateral_value - old_value + new_value
        )
    global_user.last_update_time = now
    self.global_users[user_id] = global_user
```

If `old_value` is greater than the stored value, the implementation treats it as a reset and sets the value to `new_value` instead of subtracting a negative amount.

## Uses of Global User Data

1. **Health factor**: `(total_collateral_value × liquidation_threshold) / (total_borrow_value × SCALE)`.
2. **Borrow capacity**: `max_borrow = (total_collateral_value × collateral_factor) / SCALE - total_borrow_value`.
3. **Liquidation eligibility**: Positions with health factor below the threshold are liquidatable.
4. **Withdraw limit**: Withdrawing cannot reduce collateral below what is required for existing borrows.
5. **UserHealth events**: Emitted on collateral updates for off-chain monitoring.

## Sync Flow for Price Changes

When a user interacts with a market and that market’s price changes, the flow is:

```
_sync_user_market_for_price_change(user_id, market_id)
  ├── _ensure_payment_for_fetch_price_feed()
  ├── _accrue_interest(market_id)
  ├── _fetch_price_feed(market_id)
  ├── _update_user_global_values_for_price_change(user_id, market_id)
  │     ├── _update_user_market_collatera(user_id, user, market)
  │     │     └── _update_global_collateral(user_id, old_value, new_value)
  │     └── _update_user_market_borrows(user_id, user, market)
  │           └── _update_global_borrows(user_id, old_value, new_value)
  ├── _resolve_accumulated_deposit_interest(user_id, market_id)
  └── _resolve_accumulated_borrow_interest(user_id, market_id)
```

## API

| Method | Description |
|--------|-------------|
| `get_global_user(user_id: Address)` | Returns `GlobalUserData` for the user (or default if empty). |
| `LendingPoolStorage.get_global_user_default()` | Returns the default `GlobalUserData` struct (zeros). |
