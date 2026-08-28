# Audit Engagement Guide (DOR-502)

Operational checklist for engaging an external security firm. Engineering prepares the package; leadership signs the SOW.

## 1. Pre-engagement (engineering)

- [x] Vendor engaged: **Entersoft** (Paul Kang) — $17.5k–$25k USDC, ~4 weeks incl. remediation
- [ ] Complete [internal-review-checklist.md](./internal-review-checklist.md) manual sign-off
- [ ] All tests green: `forge test --no-match-contract Fork`
- [ ] Freeze commit tagged: `audit-freeze-v1` (see [AUDIT-FREEZE.md](./AUDIT-FREEZE.md))
- [ ] Run bytecode hash script and attach output to vendor packet
- [x] Share [audit-scope.md](./audit-scope.md) + README in `docs/security/`
- [ ] GitHub read access: `@entersoftaudits`, `@entersoft-audits`

## 2. Vendor selection criteria

- Experience with lending protocols (Compound/Aave-style)
- L2 / Chainlink oracle review experience
- Upgradeable proxy (Transparent / UUPS) familiarity
- Referenceable reports in last 12 months

## 3. Suggested timeline

| Week | Activity |
|------|----------|
| 0 | Kickoff, scope confirmation, repo access |
| 1–2 | Static analysis + manual review |
| 3 | Mid-audit sync, clarifications |
| 4 | Draft report |
| 5 | Remediation window (DOR-503) |
| 6 | Retest + final report |

Target: **4–6 weeks** from kickoff to final report.

## 4. Access to provide

- GitHub read access to `df-evm` at freeze tag
- Architecture diagram (deploy topology in audit-scope)
- Test run instructions (`docs/security/README.md`)
- Contact for technical Q&A (engineering lead)

Do **not** share: production private keys, mainnet deployer mnemonics.

## 5. Budget placeholder

Record vendor, quote, and PO in Linear issue DOR-502 when approved.

## 6. Post-audit

- Triage findings into [findings-log.md](./findings-log.md)
- Fix Critical/High before mainnet (DOR-503)
- Publish summary if required by vendor license
