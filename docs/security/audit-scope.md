# External Audit Scope — DorkFi Base Mainnet (Entersoft)

**Version:** 2.0 (audit freeze)  
**Auditor:** Entersoft  
**Network:** Base mainnet (chain ID 8453)  
**Repo:** `df-evm` @ tag `audit-freeze-v1` (see bytecode hashes below)

## Executive summary

DorkFi is a cross-collateral lending pool on Base. Users deposit assets to earn yield (via per-market `NToken`) and borrow against collateral posted in other markets.

**Launch scope for this audit:** two markets only — **USDC** and **WETH**. The pool contract is generic (supports additional markets); those code paths exist but are **not enabled** on the audited mainnet deployment.

## In scope

### Core contracts (~1,550 nSLOC)

| Contract | LOC (approx) | Notes |
|----------|--------------|-------|
| `LendingPoolV2.sol` | ~1,650 | Pool logic, interest, liquidation, RBAC, pause, caps |
| `NToken.sol` | ~120 | Minted per market on `createMarket` (USDC/WETH deposits) |
| `DorkFiDeployLib.sol` | ~70 | TransparentUpgradeableProxy, ProxyAdmin, timelock helpers |
| `BaseLaunchDeploy.sol` | ~120 | Market/oracle wiring (review USDC+WETH paths; see assumptions) |
| `BaseMarketParams.sol` | ~60 | Risk parameters and soft-launch caps |
| `BaseTokens.sol` | ~20 | Base mainnet token addresses |
| `Roles.sol` | ~13 | Role constants |

### Deployment topology (audited mainnet)

```
TimelockController (48h delay)
    └── DEFAULT_ADMIN / upgrade authority
TransparentUpgradeableProxy → LendingPoolV2 (implementation locked at deploy)
    └── Two markets: USDC (6 decimals), WETH (18 decimals)
```

### User-facing operations

- `deposit` / `withdraw`
- `borrow` / `repay`
- `liquidateCrossMarket`
- Read paths: health factor, balances, APY indices

### Admin operations (in scope)

- Market creation and parameter updates
- Deposit/borrow caps
- Pause / unpause (protocol and per-market)
- `setOracle` (pointer only — oracle implementation out of scope)
- Reserve withdrawal to treasury
- Proxy upgrade via `ProxyAdmin`

## Out of scope

| Item | Rationale |
|------|-----------|
| `ChainlinkOracleRouter.sol`, `ChainlinkFeeds.sol`, `FixedPriceFeed.sol` | Oracle treated as trusted external dependency |
| `SToken.sol` / WAD borrow-only market | Not enabled at launch (`stokenMarketId` unset) |
| cbBTC market | Not enabled at launch |
| `src/MockOracle.sol`, mocks, test contracts | Test-only |
| Frontend (`base-bl-ui`) | Separate repo |
| `LendingPoolV2Hedera.sol`, Hedera / Monad / OG deployments | Non-Base chains |
| Position NFT, native ETH market, governance token | Deferred |

## Assumptions (auditor may rely on)

1. **Oracle:** An external oracle (e.g. Chainlink router) returns correct, fresh USD prices in 8 decimals. Pool integration (`IOracleRouter.getPrice`) is in scope; feed logic is not.
2. **Launch markets:** Only USDC + WETH markets are created on the audited deployment. `setStokenMarketId` is not called; cbBTC/WAD markets are not created.
3. **Tokens:** Standard ERC-20 (no fee-on-transfer, no rebasing) for USDC and WETH on Base.
4. **Admin:** `DEFAULT_ADMIN` and `ProxyAdmin` owner held by multisig + 48h timelock before mainnet (operational, not verified in this audit).
5. **SToken paths in `LendingPoolV2`:** Present in bytecode but **not exercised** at launch; review for reachability if admin misconfigures.

## Threat model priorities

1. **Fund loss** — accounting bugs, liquidation errors, interest invariants
2. **Access control** — unauthorized pause, upgrade, reserve drain, oracle pointer swap
3. **Denial of service** — griefing via caps, pause abuse
4. **Upgrade risk** — storage collision, initializer replay on proxy

## Test coverage provided

```bash
forge build
forge test --no-match-contract Fork
```

| Suite | Path |
|-------|------|
| Unit | `test/LendingPoolV2.t.sol` |
| Access control | `test/LendingPoolV2AccessControl.t.sol`, `test/security/SecurityReview.t.sol` |
| Fuzz | `test/fuzz/LendingPoolV2Fuzz.t.sol` |
| Invariant | `test/invariant/LendingPoolInvariant.t.sol` |
| Fork (optional, needs RPC) | `test/BaseLaunchFork.t.sol` |

## Bytecode freeze

At tag `audit-freeze-v1`:

```bash
forge script script/AuditBytecodeHash.s.sol -vv
```

Record:

- `LendingPoolV2` implementation creation code hash
- `NToken` creation code hash
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
- Full four-market deploy helper exists in `BaseLaunchDeploy` for future expansion; not used on audited deployment
