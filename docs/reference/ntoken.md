# NToken Role in Lending Pool

This document describes the role of NToken within the DorkFi LendingPoolV2. Implementation: `src/NToken.sol`.

## Summary

**NToken** is the non-transferable deposit receipt token for each lending market. It represents a user's supplied collateral and its accruing interest. Each market has its own NToken contract (e.g., `nUSDC` for USDC), deployed when the market is created. **LendingPool is the single source of truth** — NToken has no internal balance storage; `balanceOf`, `totalSupply`, etc. read from the pool via `ILendingPoolV2`.

## Lifecycle

### Deposit

1. User approves underlying asset transfer to the LendingPool.
2. User calls `deposit(marketId, amount)`.
3. LendingPool pulls underlying tokens from the user.
4. LendingPool mints NTokens to the user (via `NToken.mint(to, scaledAmount)`).
5. LendingPool updates scaled deposits and collateral value.

The minted amount is a **scaled amount** tied to the deposit index, not the raw deposit amount.

### Withdraw

1. User calls `withdraw(marketId, amount)`.
2. LendingPool validates sufficient NToken balance and liquidity.
3. LendingPool burns NTokens from the user (via `NToken.burnFrom(from, scaledAmount)`).
4. LendingPool transfers underlying tokens to the user.
5. LendingPool updates scaled deposits and collateral value.

### Liquidation

1. LendingPool determines unhealthy position and collateral to seize.
2. LendingPool burns NTokens from the liquidated user (`NToken.burnFrom`).
3. LendingPool mints NTokens to the liquidator as the collateral reward (`NToken.mint`).
4. Debt is repaid from liquidator; net collateral goes to liquidator.

## Design Choices

| Feature | Purpose |
|--------|---------|
| **LendingPool-only mint/burn** | Only the LendingPool can create or destroy NTokens. Users cannot mint or burn directly. |
| **Non-transferable** | `transfer` and `transferFrom` always return `false`. NTokens cannot be transferred between users. |
| **Per-market** | Each market has its own NToken, deployed when the market is created via `createMarket`. |
| **Scaled accounting** | NToken balances use scaled amounts; interest accrues through the deposit index. |
| **Single source of truth** | Balances are read from LendingPool (via `ILendingPoolV2`); NToken emits events only. |

## Integration Points

- **Market creation**: `createMarket` deploys an NToken contract and stores it in `MarketData.nToken`.
- **Deposit**: `deposit` calls `m.nToken.mint(msg.sender, scaledAmount)` after pulling underlying tokens.
- **Withdraw**: `withdraw` calls `m.nToken.burnFrom(msg.sender, scaledWithdraw)` before pushing underlying tokens.
- **Liquidation**: Burns NTokens from liquidated user; mints NTokens to liquidator.

## Related Documentation

- [LendingPoolV2](./lending-pool-v2.md) — Multi-market lending with NToken, oracle, health factor, liquidation
