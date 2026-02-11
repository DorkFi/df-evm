# DorkFi on Base — Protocol Description & Planning Spec

This document describes DorkFi as-is, maps it against Aave and Morpho, and proposes a Base-focused expansion plan including an experimental primitive for transferable NFT positions and yield-directed self-repayment.

---

## 1) DorkFi Protocol Summary (as-is)

### One-Paragraph Summary

DorkFi is a decentralized lending protocol that enables users to deposit assets (earning interest via nTokens), borrow against collateral across multiple markets, repay debt, and participate in cross-market liquidations. It uses scaled accounting for efficient interest distribution, a utilization-based interest model, and a global health-factor style liquidation system. Markets are isolated per asset with owner-configurable risk parameters; price feeds are owner-controlled (oracle-ready); and the protocol supports both protocol-wide and per-market pause, plus upgradeable contracts with future governance support.

### Core Goals (What DorkFi Optimizes For)

- **Isolated market risk**: Each asset has its own market with independent caps, rates, and risk params; long-tail assets can be onboarded without polluting core markets.
- **Scaled accounting**: Deposit/borrow in scaled units with indices; no per-user interest loops; O(1) interest accrual.
- **Global safety**: Health factor computed across all collateral and debt; cross-market liquidations allow flexible collateral seizure.
- **Operational control**: Owner can pause (protocol or market), set prices, update params, withdraw reserves; upgradeability for evolution.

### What Is Already Implied by Existing Design

| Domain | Current Design |
|--------|----------------|
| **Markets** | Per-asset markets; `create_market` deploys NToken and stores `MarketData`; markets start paused until price is set. |
| **Assets** | Collateral and borrow assets are separate markets; any market can be collateral or borrow source (except SToken borrow-only). |
| **Collateral / Borrowing** | `collateral_factor` caps max borrow; `liquidation_threshold` triggers liquidation; `close_factor` caps single liquidation size. |
| **Repay / Withdraw** | Repay reduces scaled borrows; withdraw burns nTokens and transfers underlying + accrued interest. |
| **Interest model** | Utilization-based: `rate = borrow_rate + (slope * utilization) / 10000`; accrues to `deposit_index`, `borrow_index`; `reserve_factor` splits interest to protocol. |
| **Liquidation / health** | `health = (collateral_value * liquidation_threshold) / (borrow_value * 10000)`; liquidatable when `health < 10000` (1.0); cross-market liquidation uses collateral market’s `liquidation_threshold`. |
| **Permissions** | Owner-only: create market, set price, pause, update params, withdraw reserves; `ROLE_PRICE_ORACLE` for price updates; upgrader for contract upgrades. |
| **Upgradeability** | `Upgradeable` interface; `on_update` restricted to upgrader; state preserved across upgrades. |

---

## 2) Base vs Algorand Architecture Notes

| Difference | Algorand | Base (EVM) | DorkFi Base Design Implication |
|------------|----------|------------|--------------------------------|
| **Gas / batching** | Fixed fee; group txs for atomicity | Gas per op; batch via multicall | Prefer multicall/batch entrypoints for deposit+borrow, repay+withdraw; avoid unnecessary storage writes. |
| **Keeper ecosystem** | Limited; custom bots | Gelato, Chainlink Automation, MEV bots | Design keeper-callable methods (rebalance, delever, harvest) with clear incentive model; assume third-party keepers. |
| **Oracle patterns** | Owner `set_market_price`; custom feeds | Chainlink widely available; oracle-agnostic market creation (Morpho-style) | Use Chainlink where possible; `OracleRouter` to support multiple sources; fallback to owner-set price with staleness checks. |
| **Composability** | ARC200 tokens; app calls | ERC-20; ERC-721; composable with Aave/Morpho vaults | Support ERC-20 and ERC-4626 vaults; consider adapter pattern for external liquidity. |
| **Storage model** | BoxMap, Box; app-local | Contract storage; SSTORE costs | Pack structs; avoid unbounded loops; use append-only logs where possible. |
| **Upgradeability** | App update (creator/upgrader) | Proxy (UUPS/Transparent); storage layout critical | Preserve storage layout; use append-only slots for new state; document migration for breaking changes. |

---

## 3) Competitive Map: DorkFi vs Aave vs Morpho (Mechanisms)

| Dimension | Aave V3 | Morpho Blue | DorkFi |
|-----------|---------|-------------|--------|
| **Risk topology** | Pooled (shared liquidity) or isolated mode | Isolated pair markets (collateral + loan asset per market) | Isolated per-asset markets; cross-market collateralization |
| **Parameter mutability** | Governance; risk admins | Immutable per market at creation | Owner-controlled; governance-ready |
| **Position composability** | aTokens (ERC-20); transferable | Isolated markets; no position tokens | nTokens (ERC-20–like); transferable; NFT positions in experimental primitive |
| **Liquidation** | Keeper/anyone; partial liquidation; health factor | Keeper/anyone; LLTV-based; oracle-driven | Cross-market; close_factor; health &lt; 1.0; keeper-driven |
| **Oracle** | Per-reserve oracle | Per-market oracle at creation | Owner/oracle role; Chainlink on Base |
| **Interest** | Utilization curves; aToken rebasing | Curator-set; ERC-4626 vaults | Utilization-based; scaled indices; nTokens |

### Where DorkFi Should Align with Morpho

- **Isolated risk**: Morpho’s pair markets and DorkFi’s per-asset markets both avoid shared liquidity contagion; align on “isolated by default.”
- **Oracle quality → LTV**: Higher-quality oracles justify higher LTV/LLTV; document this relationship.
- **Permissionless liquidations**: Anyone can liquidate; no whitelist.

### Where DorkFi Should Differentiate

- **Cross-market collateralization**: DorkFi allows one collateral pool to back borrows in multiple markets; Morpho is strictly per-pair.
- **Parameter mutability**: DorkFi allows owner to tune params; Morpho markets are immutable—enables faster iteration and risk tuning.
- **Experimental primitive**: NFT positions + yield-directed self-repayment + keeper rebalance—not present in Aave or Morpho core.

---

## 4) “DorkFi on Base” Minimal Viable Scope (MVS)

### Required Assets

- **Collateral**: ETH, cbETH (or wstETH)
- **Borrow**: USDC
- **Rationale**: Base-native demand; Chainlink feeds for ETH/USDC, cbETH/ETH; USDC as primary borrow asset for simplicity.

### Market Type

- **Hybrid**: Single borrow asset (USDC) initially; multiple collateral markets (ETH, cbETH).
- **Future**: Add more borrow assets as separate markets once core is stable.

### Oracle Plan

- **Primary**: Chainlink Price Feeds (ETH/USD, cbETH/ETH, USDC/USD on Base).
- **Fallback**: Owner-set price with `MAX_PRICE_AGE` (e.g., 1 hour); revert if stale.
- **OracleRouter**: Single contract that aggregates Chainlink + optional fallback; `getPrice(asset)` returns (price, timestamp).

### Roles & Admin Functions

| Role | Functions |
|------|-----------|
| Owner | `createMarket`, `pause`/`unpause`, `pauseMarket`, `setMarketParams`, `withdrawReserves`, `setOracle` |
| Price Oracle | `setMarketPrice` (if fallback used) |
| Upgrader | `upgrade` (proxy) |

### Pausing / Emergency Modes

- **Protocol pause**: Blocks deposit, withdraw, borrow, repay, liquidate, createMarket, setMarketPrice.
- **Market pause**: Blocks operations in that market only; other markets continue.
- **Recovery**: Owner unpauses after assessment; document recovery runbook.

### Events, Accounting Invariants, Upgrade Path

- **Events**: `Deposit`, `Withdraw`, `Borrow`, `Repay`, `Liquidate`, `MarketCreated`, `MarketPaused`, `ReservesWithdrawn`.
- **Invariants**: (1) `total_scaled_deposits * deposit_index >= sum(user_scaled_deposits * user_deposit_index)`; (2) health &lt; 1.0 ⇒ liquidatable; (3) no withdraw/borrow that would make health &lt; 1.0.
- **Upgrade path**: Proxy pattern; append-only storage; migration script for any new storage; timelock for upgrades (Phase 2+).

---

## 5) Experimental Primitive Proposal (Base-Native)

### Overview

A **Position NFT + Yield-Directed Self-Repayment** module: users open a leveraged yield position, receive an ERC-721 representing the position, and a keeper can rebalance/harvest to direct yield toward debt repayment. Positions have strict risk bands and an automated delever path.

### Build Option: DorkFi-Native vs Adapter

**Recommendation: DorkFi-native module.** Rationale: (1) Full control over position lifecycle, liquidation, and risk bands; (2) no dependency on Aave/Morpho upgrade cycles; (3) aligns with DorkFi’s isolated-market philosophy; (4) adapter adds complexity (approvals, vault interfaces) without clear benefit for an experimental pilot.

### Position Object (ERC-721)

| Field | Type | Semantics |
|-------|------|-----------|
| `tokenId` | uint256 | Unique position ID |
| `owner` | address | Position owner; can transfer NFT |
| `collateralMarketId` | uint64 | Market for collateral (e.g., cbETH) |
| `debtMarketId` | uint64 | Market for debt (e.g., USDC) |
| `scaledCollateral` | uint256 | Scaled collateral in PositionNFT module |
| `scaledDebt` | uint256 | Scaled debt |
| `yieldStrategy` | address | Optional: vault/adapter for yield (e.g., cbETH staking) |
| `targetLTV` | uint64 | Target LTV (bps); keeper rebalances toward this |
| `upperLTV` | uint64 | Ceiling; above this triggers delever |
| `lowerLTV` | uint64 | Floor; below this allows add collateral or harvest |
| `lastRebalance` | uint64 | Timestamp of last keeper action |
| `accruedYield` | uint256 | Yield accrued, not yet applied to debt |

**Ownership**: `ownerOf(tokenId)` = position owner; transfer of NFT transfers entire position (collateral + debt).

### Two-Leg Structure (Collateral Leg + Yield Leg)

- **Collateral leg**: User deposits collateral (e.g., cbETH) into the PositionNFT contract; it is supplied to the LendingPool (or equivalent) and counts toward the position’s collateral.
- **Yield leg**: Collateral may be in a yield source (e.g., cbETH auto-compounds). Yield accrues off-chain or via vault `totalAssets()`; keeper calls `harvest(tokenId)` to realize yield and apply it to debt.

**Yield repays debt**: On `harvest`, protocol (1) computes accrued yield (e.g., `currentValue - lastValue`), (2) uses it to repay debt (swap or direct repay if same asset), (3) updates `scaledDebt` and `accruedYield`.

### Keeper-Callable Actions

| Action | Description | Incentive |
|--------|-------------|-----------|
| `rebalance(tokenId)` | Move collateral/debt to restore `targetLTV` | Keeper fee (bps of notional) or gas reimbursement from position |
| `delever(tokenId)` | Reduce leverage when LTV &gt; `upperLTV` | Same as rebalance; priority when near liquidation |
| `harvest(tokenId)` | Realize yield and repay debt | Keeper fee from yield (e.g., 10% of harvested yield) |

**Incentive model**: Keeper registry (optional) tracks `lastKeeper` per position; fee paid in collateral or debt asset; configurable per position or global.

### Risk Bands and Automatic Unwind

| Band | Condition | Action |
|------|-----------|--------|
| Safe | LTV &lt; `lowerLTV` | Optional: harvest only; no forced action |
| Target | `lowerLTV` ≤ LTV ≤ `upperLTV` | Keeper may rebalance toward `targetLTV` |
| Danger | LTV &gt; `upperLTV` | Keeper must delever; position approaches liquidation |
| Liquidatable | health &lt; 1.0 | Standard DorkFi liquidation; NFT position liquidated like any other |

**Automatic unwind path**: When LTV &gt; `upperLTV`, keeper calls `delever`; if no keeper, position eventually becomes liquidatable. Consider: small auto-delever on any user action (e.g., repay) to nudge LTV down.

### Threat Model and Constraints

| Threat | Mitigation |
|--------|------------|
| Oracle failure | Stale price → revert or use last valid price with age check; pause market if prolonged |
| Slippage | `minCollateralReceived` in liquidations; `minOut` in harvest swaps |
| MEV | Keeper bots may front-run; use private mempool or commit-reveal for large rebalances |
| Griefing | Keeper fees bounded; no way for attacker to drain position without collateral |
| Yield source risk | Isolate yield strategy; only whitelisted vaults; caps per strategy |

### On-Chain vs Off-Chain

| On-chain | Off-chain |
|----------|-----------|
| Position state, NFT, collateral/debt balances | Yield accrual calculation (or via vault view) |
| Rebalance, delever, harvest execution | Keeper bot monitoring LTV bands |
| Liquidation (same as core DorkFi) | Alerting when positions approach `upperLTV` |
| Risk band checks | Keeper profitability simulation |

### Why This Is New Relative to Aave/Morpho

- **Transferable NFT positions**: Aave uses aTokens; Morpho has no position tokens. NFT = composable, tradeable, usable as collateral elsewhere.
- **Yield-directed self-repayment**: Alchemix-like but within DorkFi’s risk model; keeper harvests and repays automatically.
- **Strict risk bands + keeper-driven rebalance**: Combines automated risk management with explicit bands; neither Aave nor Morpho offers this as a first-class primitive.
- **Isolated + scalable**: Builds on DorkFi’s isolated markets; each position is self-contained.

---

## 6) Contract Architecture Sketch (Base)

### Module List

| Module | Responsibility |
|--------|----------------|
| **LendingPool** | Core: deposit, withdraw, borrow, repay, liquidate; market state; scaled accounting |
| **MarketManager** | createMarket, getMarket, setMarketParams; market registry |
| **NToken** | ERC-20 receipt for deposits; mint/burn on deposit/withdraw; implements scaled balance |
| **DebtToken** | Optional: ERC-20 debt representation (or use internal accounting only) |
| **PriceOracle / OracleRouter** | getPrice(asset) → (price, timestamp); Chainlink adapter + fallback |
| **LiquidationManager** | liquidateCrossMarket; health check; close_factor; bonus |
| **PositionNFT** | ERC-721; position state; integrate with LendingPool for collateral/debt |
| **StrategyAdapter / YieldModule** | Optional: wrap collateral in yield vault; harvest interface |
| **KeeperRegistry** | Optional: register keepers; fee distribution; lastKeeper per position |

### Key Public Methods (Pseudocode)

```solidity
// LendingPool
function deposit(uint64 marketId, uint256 amount) external;
function withdraw(uint64 marketId, uint256 amount) external;
function borrow(uint64 marketId, uint256 amount) external;
function repay(uint64 marketId, uint256 amount) external;

// LiquidationManager (or LendingPool)
function liquidateCrossMarket(
    uint64 debtMarketId, uint64 collateralMarketId,
    address user, uint256 debtAmount, uint256 minCollateralReceived
) external;

// MarketManager
function createMarket(uint64 tokenId, MarketParams calldata params) external returns (uint64 nTokenId);
function setMarketParams(uint64 marketId, MarketParams calldata params) external;

// OracleRouter
function getPrice(uint64 marketId) external view returns (uint256 price, uint64 timestamp);

// PositionNFT
function openPosition(uint64 collateralMarketId, uint64 debtMarketId, uint256 collateralAmount, uint256 borrowAmount, LTVBands calldata bands) external returns (uint256 tokenId);
function harvest(uint256 tokenId) external;
function rebalance(uint256 tokenId) external;
function delever(uint256 tokenId) external;
```

### Storage Layout (Upgradeability)

- Use unstructured storage proxy (e.g., EIP-1967) or namespaced slots.
- **Critical**: Do not reorder or remove existing storage slots; append new slots for new modules.
- Document slot map: `LendingPool.slot 0..N`, `MarketManager.slot N+1..`, etc.

### Where Scaled Accounting Lives

- **LendingPool**: `MarketData.total_scaled_deposits`, `total_scaled_borrows`, `deposit_index`, `borrow_index`.
- **User state**: `UserData.scaled_deposits`, `scaled_borrows` per (user, market).
- **NToken**: Balance = `scaled_balance * deposit_index / SCALE` (or equivalent); actual balance derived from pool state.

---

## 7) Development Plan (2–4 Phases)

### Phase 0: Research & Integration Spikes (4–6 weeks)

| Deliverable | Acceptance Criteria | Test Strategy |
|-------------|---------------------|---------------|
| Chainlink integration spike | Read ETH/USD, USDC/USD on Base testnet | Unit test with fork |
| OracleRouter design | Single interface for Chainlink + fallback | Mock oracle tests |
| Morpho/Aave adapter feasibility | Document adapter vs native tradeoffs | Design doc |
| Base testnet deployment | Deploy minimal LendingPool + 1 market | Manual verification |

### Phase 1: Core Markets + Basic Liquidation on Base Testnet (8–12 weeks)

| Deliverable | Acceptance Criteria | Test Strategy |
|-------------|---------------------|---------------|
| LendingPool (Solidity) | Deposit, withdraw, borrow, repay | Unit tests; invariant tests |
| NToken (ERC-20) | Mint/burn on deposit/withdraw | Unit tests |
| 2 collateral markets (ETH, cbETH) + USDC borrow | Full flow works | Integration tests |
| Cross-market liquidation | Liquidate when health &lt; 1.0 | Unit + integration |
| OracleRouter + Chainlink | Prices used in health/liquidation | Fork tests |
| Pause (protocol + market) | Blocks operations when paused | Unit tests |

### Phase 2: Audits + Mainnet Readiness (8–12 weeks)

| Deliverable | Acceptance Criteria | Test Strategy |
|-------------|---------------------|---------------|
| Internal audit | No critical/high findings | Manual review |
| External audit | Audit report; findings addressed | Audit firm |
| Fuzz tests | No crashes on random inputs | Echidna/Foundry fuzz |
| Invariant tests | Accounting invariants hold | Foundry invariant |
| Mainnet deployment plan | Runbook; parameter config | Documented |
| Timelock for upgrades | 48–72h delay | Unit test |

### Phase 3: Experimental Primitive Pilot (6–10 weeks)

| Deliverable | Acceptance Criteria | Test Strategy |
|-------------|---------------------|---------------|
| PositionNFT contract | ERC-721; open, transfer, close | Unit tests |
| Harvest / rebalance / delever | Keeper actions work | Integration tests |
| Risk bands enforcement | Delever when LTV &gt; upper | Unit tests |
| Keeper bot (reference) | Monitors and calls actions | E2E on testnet |
| Pilot on Base testnet | 5–10 positions; no critical bugs | Manual + monitoring |

---

## 8) Open Questions / Decision Log

### Q1: Single Borrow Asset vs Multiple in MVS

| Options | Recommendation | Rationale |
|---------|----------------|----------|
| A) USDC only | **A** | Simpler; sufficient for MVS; add more borrow assets in Phase 2. |
| B) USDC + ETH | B | Doubles test surface; defer. |

### Q2: Debt Representation (ERC-20 DebtToken vs Internal)

| Options | Recommendation | Rationale |
|---------|----------------|-----------|
| A) Internal accounting only | **A** | Matches Algorand design; fewer moving parts. |
| B) ERC-20 debt token | B | Composable but adds complexity; consider for Phase 3. |

### Q3: Position NFT — Include in MVS or Phase 3 Only?

| Options | Recommendation | Rationale |
|---------|----------------|-----------|
| A) Phase 3 only | **A** | MVS must ship core first; NFT is experimental. |
| B) Include in MVS | B | Too much scope; increases risk. |

### Q4: Keeper Incentive — Protocol-Funded vs User-Funded

| Options | Recommendation | Rationale |
|---------|----------------|-----------|
| A) User-funded (fee from position) | **A** | Sustainable; user opts in. |
| B) Protocol-funded | B | Requires reserve allocation; harder to scale. |
| C) Hybrid | C | Start with A; add protocol subsidy later if needed. |

### Q5: Oracle Fallback — Revert vs Use Stale

| Options | Recommendation | Rationale |
|---------|----------------|-----------|
| A) Revert if stale | **A** | Safer; prevents bad liquidations. |
| B) Use stale with cap (e.g., 1h) | B | Better availability but riskier; document clearly. |

---

*Document version: 1.0 | Target: DorkFi Base expansion | Date: Feb 2025*
