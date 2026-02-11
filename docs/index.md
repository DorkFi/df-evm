# Documentation

## Reference (implementation)

Documentation for deployed contracts and interfaces.

- [LendingPool](reference/lending-pool.md) — Phase 0: Single-asset ETH pool; deposit, withdraw, borrow, repay
- [LendingPoolV2](reference/lending-pool-v2.md) — Phase 1: Multi-market ERC20, NToken, scaled accounting, interest, oracle, health factor, liquidation
- [NToken](reference/ntoken.md) — Non-transferable deposit receipt per market; lifecycle and integration with LendingPoolV2

## Planning

High-level specs and roadmap.

- [DorkFi Base Planning Spec](planning/dorkfi-base-planning-spec.md) — Protocol description, competitive map, Base-focused expansion plan
- [Base UI Spec](planning/base-ui-spec.md) — Frontend interface for markets, portfolio, liquidation

## Deployment

- [Base Sepolia](deployment/base-sepolia.md) — Testnet deployment for LendingPoolV2 + MockOracle

## Optimizations

Gas and performance optimizations: analysis and impact.

- [Gas Savings: Caching Token Decimals](optimizations/gas-savings-decimals.md) — Caching decimals in MarketData; gas cost breakdown and scenarios

## Design & rationale

Design decisions, EVM vs AVM alignment, and implementation notes.

- [LendingPool AVM Alignment](design/lending-pool-avm-alignment.md) — EVM vs Algorand concept comparison; alignment suggestions
- [LendingPool Suggested Changes](design/lending-pool-suggested-changes.md) — Prioritized changes from AVM alignment
- [Global User Data Handling](design/global-user-data-handling.md) — Cross-market collateral and borrow aggregation; health factor inputs
- [getMaxBorrow Optimization](design/getMaxBorrow-optimization.md) — Dual view functions, sync-based recovery; Phase 1 complete
