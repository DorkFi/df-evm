# DorkFi Security Review (Phase 3)

Artifacts for internal review (DOR-501), Entersoft external audit (DOR-502), and remediation (DOR-503).

| Document | Purpose |
|----------|---------|
| [audit-scope.md](./audit-scope.md) | **Auditor scope** — Entersoft (USDC+WETH+WAD, oracle out) |
| [AUDIT-FREEZE.md](./AUDIT-FREEZE.md) | Clone, build, test, and freeze instructions |
| [internal-review-checklist.md](./internal-review-checklist.md) | Team walkthrough before external audit |
| [audit-engagement.md](./audit-engagement.md) | Vendor process and timeline |
| [findings-log.md](./findings-log.md) | Findings and remediation status |

## Quick start (auditors)

```bash
git clone --recurse-submodules <df-evm-url>
cd df-evm
git checkout audit-freeze-v1
forge build
forge test --no-match-contract Fork
forge script script/AuditBytecodeHash.s.sol -vv
```

## In-scope contracts (Entersoft)

- `src/LendingPoolV2.sol`
- `src/NToken.sol`, `src/SToken.sol`
- `src/FixedPriceFeed.sol` (WAD $1 price at launch)
- `src/access/Roles.sol`
- `src/deploy/DorkFiDeployLib.sol`, `BaseLaunchDeploy.sol`
- `src/libraries/BaseMarketParams.sol`, `BaseTokens.sol`

## Out of scope

- `ChainlinkOracleRouter` and Chainlink feeds (USDC/WETH prices trusted)
- cbBTC market
- Frontend, mocks, Hedera/other chains
