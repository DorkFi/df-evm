# DorkFi on Base — UI Specification

This document specifies the frontend interface for DorkFi on Base, covering core lending flows, market views, and liquidation.

---

## 1) Overview & Scope

### Purpose

The DorkFi Base UI enables users to interact with the lending protocol: deposit assets for yield, borrow against collateral, repay debt, and participate in liquidations.

### Target Users

| User Type | Primary Actions |
|-----------|-----------------|
| **Depositor** | Deposit assets; view supply balance, APY, nToken balance; withdraw |
| **Borrower** | Borrow against collateral; view borrow balance, health factor, max borrow; repay |
| **Liquidator** | Browse liquidatable positions; execute cross-market liquidations |

### Design Principles

- **Clarity over density**: Health factor, LTV, and risk metrics must be visible and understandable.
- **Base-native**: Wallet connect (Coinbase Smart Wallet, injected); Base chain ID; gas-conscious UX.
- **Progressive disclosure**: Core flows (deposit, borrow, repay) first; liquidation surfaced when relevant.

---

## 2) Global Layout & Navigation

### Shell

| Element | Behavior |
|---------|----------|
| **Header** | Logo; nav: Markets | Liquidate; chain selector (Base); wallet connect |
| **Network** | Base mainnet; Base Sepolia testnet |
| **Wallet** | Connect wallet; disconnect; shortened address; balance of primary asset (ETH) |
| **Footer** | Links: docs, terms, governance (future) |

### Routing

| Route | Content |
|-------|---------|
| `/` | Redirect to `/markets` |
| `/markets` | Market list + portfolio summary |
| `/markets/:marketId` | Single market detail (supply/borrow) |
| `/portfolio` | User positions across all markets; health factor |
| `/liquidate` | List of liquidatable positions |

---

## 3) Markets View

### Market List (`/markets`)

Displays all markets with aggregate stats.

| Column | Data Source | Notes |
|--------|-------------|-------|
| Asset | Token symbol (ETH, cbETH, USDC) | Icon + symbol |
| Type | Collateral | Borrow | Both |
| Supply APY | `depositIndex` + utilization model | Derived |
| Borrow APY | `borrowIndex` + utilization model | Derived |
| Total supplied | `getMarketTotalDeposits(marketId)` | Formatted with decimals |
| Total borrowed | `getMarketTotalBorrows(marketId)` | Formatted with decimals |
| Available liquidity | `getAvailableLiquidity(marketId)` | For borrow markets |
| Status | Paused / Active | `markets[].paused`, `paused` |

**Actions**: Click row → `/markets/:marketId`.

### Portfolio Summary (above market list)

| Metric | Data Source |
|--------|-------------|
| Total supplied (USD) | Sum of `getSupplyBalance(user, marketId) * price` |
| Total borrowed (USD) | Sum of `getBorrowBalance(user, marketId) * price` |
| Health factor | `getHealthFactor(user)` |
| Net APY | (supply yield − borrow cost) / collateral value |

**Health factor display**:
- &lt; 1.0: red, "Liquidatable"
- 1.0–1.2: orange, "At risk"
- &gt; 1.2: green, "Healthy"

---

## 4) Single Market View (`/markets/:marketId`)

### Layout

Two main sections: **Supply** (deposit/withdraw) and **Borrow** (borrow/repay). Tabs or side-by-side layout.

### Supply Section

| Element | Description |
|---------|-------------|
| Your supply | `getSupplyBalance(user, marketId)` |
| APY | Supply APY for this market |
| nToken balance | Display NToken balance (informational) |
| Deposit | Input amount; max = wallet balance; approve + `deposit(marketId, amount)` |
| Withdraw | Input amount; max = supply balance; `withdraw(marketId, amount)` |

**Validation**:
- Withdraw: must not reduce health factor below 1.0 (show max withdraw that keeps health ≥ 1.0).

### Borrow Section

| Element | Description |
|---------|-------------|
| Your borrow | `getBorrowBalance(user, marketId)` |
| Borrow APY | Borrow rate for this market |
| Max borrow | `getMaxBorrow(user, marketId)` |
| Health factor | `getHealthFactor(user)` (after hypothetical borrow) |
| Borrow | Input amount; max = min(wallet need, max borrow, available liquidity); `borrow(marketId, amount)` |
| Repay | Input amount; max = borrow balance; approve + `repay(marketId, amount)` |

**Validation**:
- Borrow: must not reduce health factor below 1.0.

### Risk Parameters (collapsible)

| Param | Display |
|-------|---------|
| Max LTV | `collateralFactorBps` / 100 (e.g. 80%) |
| Liquidation threshold | `liquidationThresholdBps` / 100 (e.g. 85%) |
| Liquidation penalty | `liquidationBonusBps` / 100 (e.g. 5%) |

---

## 5) Portfolio View (`/portfolio`)

### Summary

| Metric | Data Source |
|--------|-------------|
| Total supplied (USD) | Per-market supply × price |
| Total borrowed (USD) | Per-market borrow × price |
| Health factor | `getHealthFactor(user)` |
| Net APY | (supply yield − borrow cost) / collateral value |

### Position Table

| Column | Data |
|--------|------|
| Market | Asset symbol |
| Type | Supply | Borrow |
| Balance | `getSupplyBalance` or `getBorrowBalance` |
| Balance (USD) | Balance × price |
| APY | Supply or borrow APY |
| Action | Deposit | Withdraw | Borrow | Repay → link to market |

---

## 6) Liquidation View (`/liquidate`)

### Liquidatable Positions List

| Column | Data Source |
|--------|-------------|
| User | Shortened address; link to explorer |
| Debt | `getBorrowBalance(user, debtMarketId)` |
| Collateral | `getSupplyBalance(user, collateralMarketId)` |
| Health factor | `getHealthFactor(user)` |
| Debt market | USDC (or other) |
| Collateral market | ETH, cbETH, etc. |
| Action | "Liquidate" button |

**Data**: Query or index events for users with `healthFactor < 1e18`.

### Liquidation Modal

| Field | Description |
|-------|-------------|
| Debt amount | Input; max = `close_factor` × debt |
| Collateral received (min) | Slippage protection; `minCollateralReceived` |
| Preview | Estimated collateral received |
| Execute | `liquidateCrossMarket(debtMarketId, collateralMarketId, user, debtAmount, minCollateralReceived)` |

**Pre-requisites**: User must approve debt token (USDC) for LendingPool.

---

## 7) Data Requirements

### Contract Reads (View Functions)

| Function | Used In |
|----------|---------|
| `getHealthFactor(user)` | Portfolio, market, liquidation |
| `getSupplyBalance(user, marketId)` | Market, portfolio |
| `getBorrowBalance(user, marketId)` | Market, portfolio |
| `getMaxBorrow(user, marketId)` | Borrow form |
| `getAvailableLiquidity(marketId)` | Borrow form |
| `getMarketTotalDeposits(marketId)` | Market list |
| `getMarketTotalBorrows(marketId)` | Market list |
| `getDepositIndex(marketId)` | APY derivation |
| `getNToken(marketId)` | NToken balance |
| `getGlobalUser(user)` | Aggregated collateral/borrow |
| `totalMarkets()` | Market list |
| `marketIdByToken(token)` | Resolve market ID |

### Oracle / Pricing

| Source | Use |
|--------|-----|
| Oracle router | Off-chain or via wrapper contract |
| Price feeds | ETH/USD, cbETH/ETH, USDC/USD (Chainlink on Base) |

### Events (for indexing)

| Event | Use |
|-------|-----|
| `Deposit` | Update supply balance, liquidity |
| `Withdraw` | Same |
| `Borrow` | Same |
| `Repay` | Same |
| `Liquidate` | Update liquidatable list |
| `MarketCreated` | Market list |
| `MarketPaused` | Status display |

---

## 8) Error Handling & Edge States

| State | UI Behavior |
|-------|-------------|
| **Protocol paused** | Banner: "Protocol is paused"; disable all actions |
| **Market paused** | Badge on market; disable supply/borrow for that market |
| **Insufficient liquidity** | "Not enough liquidity to borrow" on borrow form |
| **Health factor would violate** | "This action would make your position liquidatable" |
| **Not liquidatable** | "Position is healthy; no liquidation needed" |
| **Wallet not connected** | CTA: "Connect wallet" |
| **Wrong network** | Banner: "Switch to Base"; prompt chain switch |
| **Transaction failed** | Toast with error; link to explorer |
| **Approval required** | Two-step: approve → deposit/repay |

---

## 9) Responsive & Accessibility

| Requirement | Implementation |
|-------------|----------------|
| Mobile | Breakpoints: &lt; 768px stacked layout; collapsible tables |
| Touch | Tap targets ≥ 44px |
| Keyboard | All actions reachable via tab; focus indicators |
| Screen reader | Semantic HTML; aria-labels for amounts and actions |
| Color | Health factor: not color-only; use icon + text |

---

## 10) Phase Alignment

| Phase | UI Scope |
|-------|----------|
| **Phase 0** | N/A (research; no public UI) |
| **Phase 1** | Markets list; single market (supply/borrow); portfolio; liquidation |
| **Phase 2** | Polish; audit findings; mainnet deployment; no new screens |

---

## 11) Open Questions / Decisions

### Q1: Wallet Priority

| Options | Recommendation | Rationale |
|---------|----------------|----------|
| A) Coinbase Smart Wallet first | **A** | Base-native; best UX for Base users |
| B) MetaMask first | B | Broader, but Base users often use Coinbase |
| C) WalletConnect + both | C | Support both; default to Coinbase on Base |

### Q2: APY Display — Supply vs Borrow

| Options | Recommendation | Rationale |
|---------|----------------|----------|
| A) Show both supply and borrow APY per market | **A** | Users need both for supply/borrow decisions |
| B) Show only when relevant (supply APY in supply section) | B | Cleaner but less discoverable |

### Q3: Liquidation — Manual List vs Subgraph

| Options | Recommendation | Rationale |
|---------|----------------|----------|
| A) Subgraph/indexer for liquidatable list | **A** | Scalable; no need to scan all users |
| B) On-chain scan (expensive) | B | Not feasible at scale |
| C) User-input address for ad-hoc liquidation | C | Supplement for power users |

---

*Document version: 1.0 | Target: DorkFi Base UI | Date: Feb 2025*
