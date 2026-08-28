# Internal Security Review Checklist (DOR-501)

Complete before external audit kickoff. Mark each item **Pass**, **Fail**, or **N/A** with notes in [findings-log.md](./findings-log.md).

**Automated checks (run on freeze commit):** `forge test --match-contract SecurityReview` and `forge test --no-match-contract Fork`

## 1. Access control

- [ ] `DEFAULT_ADMIN` held by timelock/multisig on mainnet (not EOA deployer) — *operational; N/A until deploy*
- [x] `POOL_ADMIN_ROLE` cannot pause without `PAUSER_ROLE` — automated
- [x] `PAUSER_ROLE` can pause/unpause only; cannot create markets — automated
- [x] `ORACLE_ADMIN_ROLE` can set oracle pointer; cannot withdraw reserves — automated
- [x] Treasury withdrawals restricted to `POOL_ADMIN` + `treasury` — automated
- [ ] Proxy upgrades require `ProxyAdmin` owner (timelock/multisig) — *operational; N/A until deploy*

## 2. Oracle path

*Oracle contracts out of scope for Entersoft audit; pool assumes trusted price source.*

- [x] Mainnet will use external oracle (not `MockOracle`) — documented assumption
- [ ] Stale price / sequencer checks on deployed router — *out of audit scope*
- [x] Pool reverts on failed price fetch paths — unit tests

## 3. Liquidation math

- [x] Health factor uses liquidation threshold for liquidation eligibility — unit + fuzz tests
- [x] Close factor caps partial liquidation — unit tests
- [x] Cross-market liquidation — unit + fuzz tests
- [x] SToken markets cannot be used as collateral — code + WAD enabled at launch

**Automated:** `test/LendingPoolV2Fuzz.t.sol`, `test/SToken.t.sol`, `test/BaseLaunchFork.t.sol` (WAD borrow/repay)

## 4. Pause behavior

- [ ] `deposit`, `withdraw`, `borrow`, `repay`, `liquidateCrossMarket` respect `whenNotPaused`
- [ ] Admin functions (create market, set caps) behavior documented when paused
- [ ] Emergency pause playbook documented for ops

## 5. Caps and soft launch

- [ ] `maxTotalDeposits` / `maxTotalBorrows` enforced on deposit/borrow
- [ ] Mainnet deploy uses `mainnetSoftLaunchCaps()` unless explicitly overridden
- [ ] Cap increase requires governance/timelock

**Automated:** `BaseLaunchDeploy`, mainnet deploy script tests

## 6. Interest rate invariants

- [x] Deposit indices non-decreasing — invariant tests
- [x] Borrows ≤ deposits per market — invariant tests
- [x] Pool balance covers available liquidity — invariant tests

**Automated:** `forge test --match-contract LendingPoolInvariant`

## 7. Upgradeability

- [x] Implementation locked at deploy (`IMPLEMENTATION_LOCK = 0xdead`) — automated
- [x] `initialize` callable once on proxy only — automated

## 8. Economic / MEV

- [ ] No permissionless oracle manipulation vector on mainnet path
- [ ] Liquidation incentive sufficient for keepers at expected gas costs
- [ ] Front-running on liquidations acceptable for v1 (document)

## Sign-off

| Reviewer | Date | Result |
|----------|------|--------|
| | | |
