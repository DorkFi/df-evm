# LendingPoolV2 — Phase 1 (ERC20 Focus)

## Overview

`LendingPoolV2` is the Phase 1 upgrade from the Phase 0 `LendingPoolERC20`. It introduces multi-market ERC20 lending with scaled accounting, utilization-based interest, oracle integration, health factor, cross-market liquidation, and **NToken** deposit receipts per market.

## Key Features

| Feature | Description |
|---------|-------------|
| **Multi-market** | Multiple ERC20 markets (e.g. USDC, WETH, cbETH) via `marketId` |
| **NToken** | Non-transferable deposit receipt per market; LendingPool is single source of truth |
| **Scaled accounting** | O(1) interest accrual via `depositIndex` / `borrowIndex` |
| **Utilization-based interest** | `rate = borrowRate + (slope × utilization)` |
| **Oracle** | `IOracleRouter` for cross-market collateral valuation |
| **Health factor** | `(collateral_value × liquidation_threshold) / borrow_value`; < 1 = liquidatable |
| **Cross-market liquidation** | Repay debt in one market, seize collateral from another |
| **Pause** | Protocol-level and per-market pause; owner-controlled |

## Architecture

### Market Registry

- `createMarket(token, params)` — owner creates ERC20 markets; deploys NToken per market
- `totalMarkets` — number of markets
- `marketIdByToken` — mapping from token address to market ID
- Each market has: token, NToken, scaled balances, indices, reserves, risk params

### MarketParams (createMarket)

```solidity
struct MarketParams {
    uint256 borrowRate;           // Base borrow rate (1e18)
    uint256 slope;                // Slope for utilization (1e18)
    uint256 reserveFactor;        // Reserve factor (1e18)
    uint256 collateralFactorBps;
    uint256 liquidationThresholdBps;
    uint256 closeFactorBps;
    uint256 liquidationBonusBps;
}
```

### Risk Parameters (per market)

| Param | Typical | Description |
|-------|---------|-------------|
| `collateralFactorBps` | 8000 (80%) | Max borrow as % of collateral value |
| `liquidationThresholdBps` | 8500 (85%) | Health boundary |
| `closeFactorBps` | 5000 (50%) | Max % of debt liquidatable per call |
| `liquidationBonusBps` | 500 (5%) | Liquidator incentive |

### Interest Model

- `utilization = totalBorrows / totalDeposits`
- `rate = borrowRate + (slope × utilization) / SCALE`
- Interest splits: `reserveFactor` to protocol, rest to depositors

### Pause

- **Protocol pause** (`paused`) — when true, all core functions revert with `ProtocolPaused`
- **Market pause** (`markets[].paused`) — when true, deposits/withdraws/borrows/repays in that market revert with `MarketPaused`
- Owner-only: `setPaused(bool)`, `setMarketPaused(uint64 marketId, bool)`

## Core Functions

```solidity
function deposit(uint64 marketId, uint256 amount) external;
function withdraw(uint64 marketId, uint256 amount) external;
function borrow(uint64 marketId, uint256 amount) external;
function repay(uint64 marketId, uint256 amount) external;
function liquidateCrossMarket(uint64 debtMarketId, uint64 collateralMarketId, address user, uint256 debtAmount, uint256 minCollateralReceived) external;
```

### Withdraw

Withdraw transfers underlying tokens from the pool to the user. Validations:

- **Balance** — `amount ≤ getSupplyBalance(user, marketId)`
- **Liquidity** — `amount ≤ getAvailableLiquidity(marketId)`
- **Health factor** — After withdraw, health factor must remain ≥ 1e18 (or user has no borrows)

Users can withdraw their full balance, including when it is their only collateral position.

## View Functions

```solidity
function getHealthFactor(address user) external view returns (uint256);
function getMaxBorrow(address user, uint64 marketId) external view returns (uint256);
function getSupplyBalance(address user, uint64 marketId) external view returns (uint256);
function getBorrowBalance(address user, uint64 marketId) external view returns (uint256);
function getAvailableLiquidity(uint64 marketId) external view returns (uint256);
function getDepositIndex(uint64 marketId) external view returns (uint256);
function getNToken(uint64 marketId) external view returns (address);
function getScaledDeposits(address user, uint64 marketId) external view returns (uint256);
function getTotalScaledDeposits(uint64 marketId) external view returns (uint256);
function getMarketTotalDeposits(uint64 marketId) external view returns (uint256);
function getMarketTotalBorrows(uint64 marketId) external view returns (uint256);
function getGlobalUser(address user) external view returns (GlobalUserData memory);
function getGlobalUserDefault() public pure returns (GlobalUserData memory);
```

## Admin Functions

```solidity
function setPaused(bool _paused) external;  // onlyOwner
function setMarketPaused(uint64 marketId, bool _paused) external;  // onlyOwner
function setOracle(address newOracle) external;  // onlyOwner
```

## Custom Errors

| Error | When |
|-------|------|
| `MarketNotFound` | Market does not exist |
| `InvalidAmount` | Zero amount or failed minCollateralReceived in liquidation |
| `InsufficientCollateral` | Borrow exceeds max allowed |
| `InsufficientLiquidity` | Supply/borrow amount exceeds available liquidity |
| `InsufficientBalance` | Withdraw exceeds user balance |
| `HealthFactorWouldViolate` | Withdraw or borrow would make position unhealthy |
| `NotLiquidatable` | User health factor ≥ 1e18 |
| `InvalidHealthFactor` | Reserved |
| `Unauthorized` | Not owner |
| `TransferFailed` | ERC20 transfer failed |
| `TokenAlreadyHasMarket` | Token already has a market |
| `ProtocolPaused` | Protocol is paused |
| `MarketPaused` | Market is paused |

## NToken

Each market has an **NToken** — a non-transferable deposit receipt. NToken name/symbol/decimals are bootstrapped from the underlying token (e.g. "DorkFi USDC", "nUSDC"). LendingPool holds all state; NToken reads balances via `ILendingPoolV2`. See [NToken Role](./ntoken.md) for lifecycle and integration details.

## Interfaces

- **ILendingPoolV2** — Minimal interface for NToken to read balance data from the pool:
  - `getDepositIndex(marketId)`, `getSupplyBalance(user, marketId)`, `getMarketTotalDeposits(marketId)`, `getScaledDeposits(user, marketId)`, `getTotalScaledDeposits(marketId)`

## Files

- `src/LendingPoolV2.sol` — main contract
- `src/NToken.sol` — non-transferable deposit receipt per market
- `src/interfaces/ILendingPoolV2.sol` — interface for NToken balance reads
- `src/interfaces/IOracleRouter.sol` — oracle interface
- `src/MockOracle.sol` — mock for testing (Chainlink-style 8 decimals)
- `src/ChainlinkOracleRouter.sol` — Chainlink AggregatorV3 adapter (production)
- `src/libraries/ChainlinkFeeds.sol` — known Base feed proxy addresses
- `src/mocks/MockERC20.sol` — test token
- `script/LendingPoolV2.s.sol` — deployment script (MockOracle)
- `script/ChainlinkOracleRouter.s.sol` — deploy Chainlink router + optional `setOracle`
- `test/LendingPoolV2.t.sol` — pool tests
- `test/ChainlinkOracleRouter.t.sol` — oracle router tests

## Deployment

1. Deploy `MockOracle` (testnets) or `ChainlinkOracleRouter` (Base / production)
2. Deploy `LendingPoolV2(oracle)`
3. Call `createMarket(token, params)` for each ERC20
4. Set prices: `MockOracle.setPrice(marketId, price)` **or** `ChainlinkOracleRouter.setFeed(marketId, aggregator)`
5. Optional: `setOracle(address)` or `setPaused(bool)` for production config

See [Chainlink Oracle Integration](../planning/chainlink-oracle-integration.md) for the cutover checklist.
