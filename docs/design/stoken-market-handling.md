# SToken Market Handling (EVM)

## Overview

The protocol supports a **borrow-only** market backed by the SToken contract. The stoken market has no user deposits or collateral; it is used only for borrowing and repaying. Core methods in `src/LendingPoolV2.sol` treat this market specially so that interest, transfers, and access control behave correctly.

This document mirrors the AVM app’s SToken market handling and lists which core methods have special handling for the stoken market and what that handling does.

## Configuration

- **State:** `stokenMarketId` (uint64) — market ID of the borrow-only SToken market. Set by the owner via `setStokenMarketId(marketId)`. Use `type(uint64).max` to indicate no stoken market (default).
- **Identification:** A market is the stoken market when `marketId == stokenMarketId`.
- **Creation:** The owner creates a market whose underlying token is an SToken contract (with LendingPool as minter), then calls `setStokenMarketId(marketId)` for that market.

## Internal Logic

### Utilization (in `_accrueInterest`)

- **Behavior:** For the stoken market, utilization is **100%** (`SCALE`).
- **Reason:** There are no deposits; treating utilization as 100% keeps borrow-rate and interest math consistent for the borrow-only market.

### Interest split (in `_accrueInterest`)

- **Behavior:** For the stoken market, **all interest is assigned to reserves** (`toReserves = interest`, `toDepositors = 0`).
- **Reason:** No depositors to pay; protocol captures full interest.

### `_accrueInterest`

- **Behavior:** Uses the utilization and interest-split rules above. Borrow index is still updated for the stoken market; deposit index is only updated when `totalScaledDeposits > 0` and `toDepositors > 0`.
- **Reason:** Stoken markets must accrue interest on borrows even though there is no depositor interest.

### `_debtBorrow`

- **Behavior:** For the stoken market, calls **`ISToken(token).mint(beneficiary, amount)`**. Otherwise uses `_push` (transfer from pool).
- **Reason:** Stoken is minted on borrow; there is no pool balance to transfer.

### `_debtRepay`

- **Behavior:** For the stoken market, calls **`ISToken(token).burnFrom(payer, amount)`**. Otherwise uses `_pull` (transferFrom payer to pool).
- **Reason:** Repayment destroys stoken instead of sending it to the pool.

### Deposit / Withdraw

- **Behavior:** `_deposit` and `_withdraw` revert with **`CannotUseStokenMarketForThisOperation()`** when `marketId` is the stoken market.
- **Reason:** Prevents deposit/withdraw flows from targeting the borrow-only stoken market.

### `_borrow` liquidity check

- **Behavior:** For the stoken market, the **available liquidity check** (totalDeposits − totalBorrows) is **skipped**. Borrow is still limited by `maxTotalBorrows` and by health factor (collateral in other markets).
- **Reason:** Stoken market has no deposits; borrows are backed only by collateral in other markets.

## Public / Owner Methods

### `withdrawReserves`

- **Behavior:** For the stoken market, **mints** tokens to the owner via `ISToken(token).mint(owner, amount)`. For other markets, transfers existing underlying from the pool to the owner.
- **Reason:** Stoken market has no deposit-side balance; reserves are withdrawn by minting.

### `liquidate` / `_liquidateCrossMarket`

- **Behavior:** Reverts with **`StokenMarketCannotBeCollateral()`** when **`collateralMarketId == stokenMarketId`**.
- **Reason:** Stoken positions are borrow-only; there is no stoken collateral to seize in liquidation.

## Operations That Disallow Stoken Market

| Operation   | Entry point   | Effect                                      |
|------------|----------------|---------------------------------------------|
| **Deposit**  | `_deposit`     | Stoken market cannot be used for deposits.  |
| **Withdraw** | `_withdraw`    | Stoken market cannot be used for withdrawals. |

Borrow and repay use the stoken market when `marketId == stokenMarketId` and are the only supported actions for that market.

## Summary

| Concern                | Stoken behavior |
|------------------------|-----------------|
| Deposits / withdrawals | Not allowed (`CannotUseStokenMarketForThisOperation`). |
| Borrow                 | Allowed; uses `ISToken.mint`. |
| Repay                  | Allowed; uses `ISToken.burnFrom`. |
| Utilization            | Treated as 100%. |
| Interest distribution  | All to reserves. |
| Reserve withdrawal     | Mint to owner. |
| Liquidation collateral | Stoken market cannot be used as collateral (`StokenMarketCannotBeCollateral`). |

The stoken market is a **borrow-only** market: debt is created by minting and reduced by burning on the SToken contract, with no deposit or collateral accounting in the pool for that market.
