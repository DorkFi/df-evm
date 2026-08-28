# External Audit Scope — DorkFi Base Mainnet (Entersoft)

**Version:** 2.1 (audit freeze)  
**Auditor:** Entersoft  
**Network:** Base mainnet (chain ID 8453)  
**Repo:** `df-evm` @ tag `audit-freeze-v1` (see bytecode hashes below)

## Executive summary

DorkFi is a cross-collateral lending pool on Base. Users deposit assets to earn yield (via per-market `NToken`) and borrow against collateral posted in other markets.

**Launch scope for this audit:** three markets on Base:

| Market | Asset | Role |
|--------|-------|------|
| USDC | Circle USDC (6 decimals) | Deposit, borrow, collateral |
| WETH | Canonical WETH (18 decimals) | Deposit, borrow, collateral |
| WAD | `SToken` (6 decimals) | **Borrow-only** — minted debt token, not collateral |

cbBTC and additional markets are **out of scope** for this audit / launch.

## In scope

### Core contracts (~1,750 nSLOC)

| Contract | LOC (approx) | Notes |
|----------|--------------|-------|
| `LendingPoolV2.sol` | ~1,650 | Pool logic, interest, liquidation, RBAC, SToken borrow paths |
| `NToken.sol` | ~120 | Per-market deposit receipt (USDC, WETH) |
| `SToken.sol` | ~136 | Borrow-only debt token (WAD market) |
| `FixedPriceFeed.sol` | ~55 | WAD USD price ($1 fixed) — deployed at launch |
| `DorkFiDeployLib.sol` | ~70 | TransparentUpgradeableProxy, ProxyAdmin, timelock helpers |
| `BaseLaunchDeploy.sol` | ~120 | Canonical market setup including WAD/SToken wiring |
| `BaseMarketParams.sol` | ~60 | Risk parameters and soft-launch caps |
| `BaseTokens.sol` | ~20 | Base mainnet token addresses |
| `Roles.sol` | ~13 | Role constants |

### Deployment topology (audited mainnet)

```
TimelockController (48h delay)
    └── DEFAULT_ADMIN / upgrade authority
TransparentUpgradeableProxy → LendingPoolV2 (implementation locked at deploy)
    ├── USDC market (NToken)
    ├── WETH market (NToken)
    └── WAD market (SToken, borrow-only; setStokenMarketId)
FixedPriceFeed → WAD/USD ($1) wired via external oracle router (router out of scope)
```

### User-facing operations

- `deposit` / `withdraw` (USDC, WETH)
- `borrow` / `repay` (USDC, WETH, WAD)
- `liquidateCrossMarket`
- Read paths: health factor, balances, APY indices

### WAD / SToken-specific (in scope)

- `setStokenMarketId` on deploy
- SToken mint/burn authorized by pool only
- WAD cannot be used as collateral (`_isStokenMarket` checks)
- Reserve withdrawal mints SToken to treasury on WAD market

### Admin operations (in scope)

- Market creation and parameter updates
- Deposit/borrow caps (including WAD borrow cap)
- Pause / unpause (protocol and per-market)
- `setOracle` (pointer only — Chainlink router out of scope)
- Reserve withdrawal to treasury
- Proxy upgrade via `ProxyAdmin`

## Out of scope

| Item | Rationale |
|------|-----------|
| `ChainlinkOracleRouter.sol`, `ChainlinkFeeds.sol` | Chainlink oracle treated as trusted external dependency |
| cbBTC market | Not enabled at launch |
| `src/MockOracle.sol`, mocks, test contracts | Test-only |
| Frontend (`base-bl-ui`) | Separate repo |
| `LendingPoolV2Hedera.sol`, Hedera / Monad / OG deployments | Non-Base chains |
| Position NFT, native ETH market, governance token | Deferred |

## Assumptions (auditor may rely on)

1. **Chainlink oracle:** Returns correct, fresh USD prices for USDC and WETH in 8 decimals. Router implementation not audited; pool `IOracleRouter.getPrice` integration is in scope.
2. **WAD price:** `FixedPriceFeed` returns $1.00 (8 decimals) for WAD; not manipulable by users.
3. **Launch markets:** USDC, WETH, and WAD only. cbBTC market is not created on audited deployment.
4. **Tokens:** Standard ERC-20 (no fee-on-transfer, no rebasing).
5. **Admin:** `DEFAULT_ADMIN` and `ProxyAdmin` owner held by multisig + 48h timelock before mainnet (operational).

## Threat model priorities

1. **Fund loss** — accounting bugs, liquidation errors, SToken mint/burn authorization
2. **Access control** — unauthorized pause, upgrade, reserve drain, oracle pointer swap
3. **WAD borrow-only** — WAD used as collateral, unauthorized SToken mint, reserve mint abuse
4. **Upgrade risk** — storage collision, initializer replay on proxy

## Test coverage provided

```bash
forge build
forge test --no-match-contract Fork
```

| Suite | Path |
|-------|------|
| Unit | `test/LendingPoolV2.t.sol`, `test/SToken.t.sol` |
| Access control | `test/LendingPoolV2AccessControl.t.sol`, `test/security/SecurityReview.t.sol` |
| Fuzz | `test/fuzz/LendingPoolV2Fuzz.t.sol` |
| Invariant | `test/invariant/LendingPoolInvariant.t.sol` |
| Fork (optional, needs RPC) | `test/BaseLaunchFork.t.sol` (includes WAD borrow/repay) |

## Bytecode freeze

At tag `audit-freeze-v1`:

```bash
forge script script/AuditBytecodeHash.s.sol -vv
```

Record:

- `LendingPoolV2` implementation creation code hash
- `NToken` creation code hash
- `SToken` creation code hash
- `FixedPriceFeed` creation code hash
- Compiler: Solidity 0.8.x, `via_ir = true`, `optimizer_runs = 200`
- OpenZeppelin `v5.1.0` (proxy, timelock, AccessControl — dependency, unmodified)

## Deliverables (Entersoft SOW)

- Severity-classified findings (Critical / High / Medium / Low / Informational)
- Remediation recommendations
- One remediation review cycle
- Final report suitable for publication

## Known limitations (documented, not bugs)

- `MockOracle` is test-only and has no access control
- Soft-launch caps limit TVL at launch (`BaseMarketParams.mainnetSoftLaunchCaps`)
- `BaseLaunchDeploy.createCanonicalMarkets` can wire cbBTC for future expansion; not used on audited deployment
