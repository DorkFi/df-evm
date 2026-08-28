# Audit Freeze Checklist

Use this checklist when tagging `audit-freeze-v1` for Entersoft.

## Pre-freeze (engineering)

- [x] RBAC, proxy, timelock on `LendingPoolV2`
- [x] Unit, fuzz, invariant, and security review tests
- [x] Scope doc aligned with Entersoft (USDC+WETH, oracle out)
- [x] `forge test --no-match-contract Fork` green on freeze commit (`e92371e`)
- [ ] GitHub read access for `@entersoftaudits` and `@entersoft-audits`

## Freeze steps

```bash
# 1. Ensure clean working tree on intended commit
git status

# 2. Run tests
forge build
forge test --no-match-contract Fork

# 3. Record bytecode hashes (paste output into Entersoft kickoff email)
forge script script/AuditBytecodeHash.s.sol -vv

# 4. Tag and push
git tag -a audit-freeze-v1 -m "Entersoft audit: Base USDC+WETH lending pool"
git push origin audit-freeze-v1
```

## Send to Entersoft

1. Tag name: `audit-freeze-v1`
2. Commit SHA: `e92371e` (verify: `git rev-parse audit-freeze-v1^{commit}`)
3. Link: `docs/security/audit-scope.md`
4. Bytecode hashes (at freeze):
   - `LendingPoolV2`: `0x0ed58307edbc36bbf8654305c32b416045fae01239becdb13c359ce1c424d377`
   - `NToken`: `0x35c4b6793967771e42d614e8d6feb359d1fb2a4026cb5fca6c5699fe0aa97a63`
5. Confirm scope: USDC + WETH only; oracle out of scope; ~$18k / 4 weeks per SOW

## Post-freeze

- No changes on `audit-freeze-v1` without notifying Entersoft
- Fixes go on a branch; retest against new commit after remediation
- Log findings in [findings-log.md](./findings-log.md)
