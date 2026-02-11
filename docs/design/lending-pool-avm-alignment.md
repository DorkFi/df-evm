# LendingPool (EVM) vs AVM Concept — Differences and Alignment Suggestions

This document compares the candidate EVM LendingPool implementation (Base) against the AVM (Algorand) DorkFi concept and proposes changes to align the EVM design more closely with the established protocol.

---

## Executive Summary

The current EVM LendingPool is a **simplified single-asset ETH pool** suitable for an MVP or proof-of-concept. It omits many concepts central to the AVM design: multi-market architecture, interest accrual, scaled accounting, NTokens, cross-market collateralization, liquidations, and risk parameters. The suggestions below outline a path to bring the Base implementation closer to the AVM concept while respecting EVM constraints.

### Base Deployment Note

An **ETH lending pool will not be used on Base** — there is no incentive, and WETH and cbETH are readily available. For simplicity, ETH is treated as a gas token only. WETH and cbETH will be added to the **primary lending pool** that is able to mint WAD.

---

## 1. Architecture Comparison

| Dimension | AVM (Algorand) DorkFi | EVM LendingPool (Current) | Gap |
|-----------|------------------------|---------------------------|-----|
| ** markets** | Per-asset markets; `create_market` | Single pool (ETH only) | No multi-market support |
| **Deposit representation** | NToken (ERC-20–like, mint/burn) | Raw `supplyBalance` mapping | No composable receipts |
| **Accounting** | Scaled (indices, O(1) interest) | Raw balances | No interest accrual |
| **Interest model** | Utilization-based (rate = base + slope × util) | None | No yield for depositors |
| **Collateral** | Cross-market; any collateral backs any borrow | Single asset only | No flexibility |
| **Health / liquidation** | Health factor; cross-market liquidation | Not implemented | No safety net |
| **Risk params** | collateral_factor, liquidation_threshold, close_factor, liquidation_bonus | Fixed 80% COL only | No risk tuning |
| **Price** | Oracle (owner or feed) | Implicit (ETH = 1:1) | No pricing for cross-asset |
| **Protocol reserves** | reserve_factor; withdraw_reserves | None | No protocol revenue |
| **Pause** | Protocol + per-market | None | No emergency controls |

---

## 2. Major Conceptual Differences

### 2.1 Single Asset vs Multi-Market

**AVM**: Each asset has its own market. Users deposit into multiple markets (ETH, cbETH, USDC, etc.) and borrow against their combined collateral. Position health is computed across all markets.

**EVM current**: One pool, one asset (ETH). No notion of “markets” or multiple assets.

**Suggestion**: Introduce a `MarketManager` and `marketId`-scoped operations. Even for an MVS, support at least:
- 2 collateral markets (e.g., WETH, cbETH)
- 1 borrow market (e.g., USDC)

```
// Target signature
function deposit(uint64 marketId, uint256 amount) external;
function borrow(uint64 marketId, uint256 amount) external;
```

---

### 2.2 Raw Balances vs Scaled Accounting

**AVM**: Uses scaled units and indices:
- `scaled_deposits`, `scaled_borrows` per user
- `deposit_index`, `borrow_index` per market
- `actual_value = scaled_value * index / SCALE`

**EVM current**: Direct `supplyBalance[user]` and `borrowBalance[user]`.

**Suggestion**: Move to scaled accounting:
- Store `userScaledDeposits[marketId][user]`, `userScaledBorrows[marketId][user]`
- Per-market: `totalScaledDeposits`, `totalScaledBorrows`, `depositIndex`, `borrowIndex`
- Accrue interest on every state-changing call via `_accrueInterest(marketId)`

This enables O(1) interest distribution without per-user loops and matches AVM behavior.

---

### 2.3 No NToken vs NToken Receipts

**AVM**: Deposits mint NTokens; withdrawals burn NTokens. NTokens are transferable (within constraints) and composable.

**EVM current**: No receipts; only internal balances.

**Suggestion**: Add an **NToken** ERC-20 per market:
- Mint on deposit, burn on withdraw
- Balance = `scaledBalance * depositIndex / SCALE`
- Matches AVM nToken concept and enables composability (e.g., use in other DeFi protocols)

---

### 2.4 No Interest vs Utilization-Based Interest

**AVM**: Interest accrues via utilization-based model:
- `utilization = total_borrows / total_deposits`
- `rate = borrow_rate + (slope * utilization) / SCALE`
- Interest flows to deposit_index, borrow_index, and reserves

**EVM current**: No interest; depositors earn nothing, borrowers pay nothing.

**Suggestion**: Implement the same model:
- Per-market: `borrowRate`, `slope`, `reserveFactor`
- On each deposit/withdraw/borrow/repay: call `_accrueInterest(marketId)`
- Update `depositIndex`, `borrowIndex`, `reserves`

---

### 2.5 Collateral Factor Only vs Full Risk Framework

**AVM**: Uses:
- `collateral_factor` — max borrow as % of collateral value
- `liquidation_threshold` — health < 1.0 boundary
- `close_factor` — max % of debt liquidatable per call
- `liquidation_bonus` — incentive for liquidators

**EVM current**: Single `COLLATERAL_FACTOR_BPS = 8000` (80%).

**Suggestion**: Add per-market risk parameters:
- `collateralFactor` (e.g., 8000 bps)
- `liquidationThreshold` (e.g., 8500 bps)
- `closeFactor` (e.g., 5000 bps)
- `liquidationBonus` (e.g., 500 bps)

---

### 2.6 No Health Factor vs Global Health

**AVM**: Health computed across all collateral and debt:
```python
health = (total_collateral_value * liquidation_threshold) / (total_borrow_value * SCALE)
# liquidatable if health < 1.0
```

**EVM current**: No health factor; only collateral factor check at borrow time.

**Suggestion**: Add `getHealthFactor(user)` and enforce:
- No borrow/withdraw that would make health < 1.0
- Liquidatable when health < 1.0

---

### 2.7 No Liquidations vs Cross-Market Liquidations

**AVM**: `liquidate_cross_market(debtMarketId, collateralMarketId, user, debtAmount, minCollateralReceived)`.

**EVM current**: No liquidation support.

**Suggestion**: Implement `liquidateCrossMarket`:
- Require health < 1.0
- Liquidator repays debt in debt market
- Seize collateral from collateral market (with bonus)
- Enforce `close_factor` and `minCollateralReceived`

---

### 2.8 Implicit Pricing vs Oracle

**AVM**: Prices come from oracle (owner-set or external feed). Used for collateral valuation and liquidation.

**EVM current**: ETH-only pool; no explicit price (effectively 1:1).

**Suggestion**: Add `OracleRouter` / `PriceOracle`:
- `getPrice(marketId)` → (price, timestamp)
- Integrate Chainlink for Base
- Use prices for cross-market collateral value and liquidation amounts

---

### 2.9 No Pause vs Protocol + Market Pause

**AVM**: `pause()` (protocol-wide) and `pauseMarket(marketId)` (per-market).

**EVM current**: No pause.

**Suggestion**: Add:
- `protocolPaused`
- `marketPaused[marketId]`
- Block deposit, withdraw, borrow, repay, liquidate when paused

---

### 2.10 No Reserves vs Protocol Reserves

**AVM**: `reserve_factor` routes some interest to protocol; `withdraw_reserves(marketId, amount)` for owner.

**EVM current**: No reserves.

**Suggestion**: Add per-market `reserves` and `withdrawReserves(marketId, amount)` (owner-only).

---

## 3. Suggested Additions to EVM LendingPool

### 3.1 State Variables (Target)

```solidity
// Market registry
uint64 public totalMarkets;
mapping(uint64 => MarketData) public markets;

// Per-market, per-user scaled balances
mapping(uint64 => mapping(address => uint256)) public userScaledDeposits;
mapping(uint64 => mapping(address => uint256)) public userScaledBorrows;

// Global user aggregates (for cross-market health)
mapping(address => uint256) public totalCollateralValue;  // or compute on-demand
mapping(address => uint256) public totalBorrowValue;

// NToken per market
mapping(uint64 => address) public nTokens;

// Oracle
IOracleRouter public oracle;

// Pause
bool public protocolPaused;
mapping(uint64 => bool) public marketPaused;
```

### 3.2 Core Functions (Target)

```solidity
// Market management (owner)
function createMarket(uint64 tokenId, MarketParams calldata params) external returns (uint64 nTokenId);
function setMarketParams(uint64 marketId, MarketParams calldata params) external;

// Core operations (market-scoped)
function deposit(uint64 marketId, uint256 amount) external;
function withdraw(uint64 marketId, uint256 amount) external;
function borrow(uint64 marketId, uint256 amount) external;
function repay(uint64 marketId, uint256 amount) external;

// Liquidation
function liquidateCrossMarket(
    uint64 debtMarketId, uint64 collateralMarketId,
    address user, uint256 debtAmount, uint256 minCollateralReceived
) external;

// Admin
function pause(bool paused) external;  // protocol
function pauseMarket(uint64 marketId, bool paused) external;
function withdrawReserves(uint64 marketId, uint256 amount) external;
function setOracle(address newOracle) external;

// View
function getHealthFactor(address user) external view returns (uint256);
function getMaxBorrow(address user, uint64 marketId) external view returns (uint256);
```

### 3.3 Interest Accrual (Pseudocode)

```solidity
function _accrueInterest(uint64 marketId) internal {
    MarketData storage m = markets[marketId];
    uint256 elapsed = block.timestamp - m.lastUpdateTime;
    if (elapsed == 0) return;

    uint256 totalBorrows = (m.totalScaledBorrows * m.borrowIndex) / SCALE;
    uint256 totalDeposits = (m.totalScaledDeposits * m.depositIndex) / SCALE;
    uint256 utilization = totalDeposits == 0 ? 0 : (totalBorrows * SCALE) / totalDeposits;
    uint256 rate = m.borrowRate + (m.slope * utilization) / SCALE;
    uint256 interest = (rate * totalBorrows * elapsed) / (SECONDS_PER_YEAR * SCALE);

    uint256 toReserves = (interest * m.reserveFactor) / SCALE;
    uint256 toDepositors = interest - toReserves;

    m.reserves += toReserves;
    if (m.totalScaledBorrows > 0)
        m.borrowIndex += (interest * SCALE) / m.totalScaledBorrows;
    if (m.totalScaledDeposits > 0)
        m.depositIndex += (toDepositors * SCALE) / m.totalScaledDeposits;
    m.lastUpdateTime = block.timestamp;
}
```

---

## 4. Recommendation Summary

| Priority | Change | Rationale |
|----------|--------|-----------|
| **P0** | Multi-market + `marketId` in signatures | Core AVM concept; enables MVS with WETH, cbETH, USDC |
| **P0** | Scaled accounting + indices | Required for interest; matches AVM; O(1) accrual |
| **P0** | Utilization-based interest model | Depositors earn yield; borrowers pay; protocol sustainability |
| **P0** | Oracle + price feeds | Needed for cross-market collateral valuation |
| **P0** | Health factor + liquidation | Essential for protocol safety |
| **P1** | NToken per market | Composable; aligns with AVM; ERC-20 receipt |
| **P1** | Full risk params (liquidation_threshold, close_factor, bonus) | Proper liquidation behavior |
| **P1** | Protocol + market pause | Emergency controls |
| **P2** | Reserve factor + withdraw_reserves | Protocol revenue |
| **P2** | Market caps (max deposits/borrows) | Risk management |

---

## 5. Migration Path

1. **Phase 0**: Keep current LendingPool as a minimal single-asset reference; document it as “simplified MVP.”
2. **Phase 1**: Implement `LendingPoolV2` (or extend) with:
   - Market registry + `marketId`
   - Scaled accounting
   - Interest accrual
   - Oracle integration
   - Health factor + liquidation
3. **Phase 2**: Add NToken, full risk params, pause, reserves.
4. **Phase 3**: Add experimental Position NFT primitive per Base planning spec.

---

*Document version: 1.0 | Target: DorkFi Base EVM alignment with AVM concept | Date: Feb 2025*
