# LendingPool — Suggested Changes (AVM Alignment)

This document outlines suggested changes to the LendingPool based on the [LendingPool-AVM-Alignment](./lending-pool-avm-alignment.md) document.

### Base Deployment Note

An **ETH lending pool will not be used on Base** — there is no incentive, and WETH and cbETH are readily available. For simplicity, ETH is treated as a gas token only. WETH and cbETH will be added to the **primary lending pool** that is able to mint WAD.

---

## Priority Overview

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

## P0 — Core Changes

### 1. Multi-Market + `marketId`

- Introduce `MarketManager` and `marketId`-scoped operations
- Support at least 2 collateral markets (e.g., ETH, cbETH) and 1 borrow market (e.g., USDC)
- Target signatures:

```solidity
function deposit(uint64 marketId, uint256 amount) external;
function withdraw(uint64 marketId, uint256 amount) external;
function borrow(uint64 marketId, uint256 amount) external;
function repay(uint64 marketId, uint256 amount) external;
```

### 2. Scaled Accounting + Indices

- Replace raw `supplyBalance[user]` and `borrowBalance[user]` with scaled balances
- Store `userScaledDeposits[marketId][user]`, `userScaledBorrows[marketId][user]`
- Per-market: `totalScaledDeposits`, `totalScaledBorrows`, `depositIndex`, `borrowIndex`
- Formula: `actual_value = scaled_value * index / SCALE`
- Call `_accrueInterest(marketId)` on every state-changing operation

### 3. Utilization-Based Interest

- Per-market: `borrowRate`, `slope`, `reserveFactor`
- `utilization = total_borrows / total_deposits`
- `rate = borrow_rate + (slope * utilization) / SCALE`
- On each deposit/withdraw/borrow/repay: update `depositIndex`, `borrowIndex`, `reserves`

### 4. Oracle + Price Feeds

- Add `OracleRouter` / `PriceOracle`: `getPrice(marketId)` → (price, timestamp)
- Integrate Chainlink for Base
- Use prices for cross-market collateral value and liquidation amounts

### 5. Health Factor + Liquidation

- Add `getHealthFactor(user)` computed across all collateral and debt
- `health = (total_collateral_value * liquidation_threshold) / (total_borrow_value * SCALE)`
- Enforce: no borrow/withdraw that would make health < 1.0
- Liquidatable when health < 1.0
- Implement `liquidateCrossMarket(debtMarketId, collateralMarketId, user, debtAmount, minCollateralReceived)`

---

## P1 — Important Additions

### 6. NToken per Market

- ERC-20 receipt per market: mint on deposit, burn on withdraw
- Balance = `scaledBalance * depositIndex / SCALE`
- Enables composability (e.g., use in other DeFi protocols)

### 7. Full Risk Parameters

- `collateralFactor` (e.g., 8000 bps)
- `liquidationThreshold` (e.g., 8500 bps)
- `closeFactor` (e.g., 5000 bps)
- `liquidationBonus` (e.g., 500 bps)

### 8. Protocol + Market Pause

- `protocolPaused` global flag
- `marketPaused[marketId]` per-market
- Block deposit, withdraw, borrow, repay, liquidate when paused

---

## P2 — Nice to Have

### 9. Protocol Reserves

- `reserve_factor` routes some interest to protocol
- `withdrawReserves(marketId, amount)` (owner-only)

### 10. Market Caps

- Max deposits/borrows per market for risk management

---

## Target State Variables

```solidity
// Market registry
uint64 public totalMarkets;
mapping(uint64 => MarketData) public markets;

// Per-market, per-user scaled balances
mapping(uint64 => mapping(address => uint256)) public userScaledDeposits;
mapping(uint64 => mapping(address => uint256)) public userScaledBorrows;

// NToken per market
mapping(uint64 => address) public nTokens;

// Oracle
IOracleRouter public oracle;

// Pause
bool public protocolPaused;
mapping(uint64 => bool) public marketPaused;
```

---

## Target Core Functions

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
function pause(bool paused) external;
function pauseMarket(uint64 marketId, bool paused) external;
function withdrawReserves(uint64 marketId, uint256 amount) external;
function setOracle(address newOracle) external;

// View
function getHealthFactor(address user) external view returns (uint256);
function getMaxBorrow(address user, uint64 marketId) external view returns (uint256);
```

---

## Migration Path

1. **Phase 0**: Keep current LendingPool as minimal single-asset reference; document as "simplified MVP" ✓
2. **Phase 1**: Implement `LendingPoolV2` with market registry, scaled accounting, interest accrual, oracle, health factor, liquidation ✓
3. **Phase 2**: Add NToken, full risk params, pause, reserves
4. **Phase 3**: Add experimental Position NFT primitive per Base planning spec

---

*Source: [LendingPool-AVM-Alignment](./lending-pool-avm-alignment.md)*
