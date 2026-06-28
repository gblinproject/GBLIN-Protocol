# GBLIN Protocol — Audit Reports

This directory contains all formal audit reports and security reviews of the GBLIN Protocol smart contracts.

## Status

| Stage | Status | Date |
|---|---|---|
| Internal review | ✅ Completed | 2026-04 |
| Public source verification (BaseScan) | ✅ Verified | 2026-04 |
| Slither static analysis (V6) | ✅ Completed — **0 critical / 0 high** | 2026-06 |
| External audit | 🟡 Open to community review | — |
| Formal verification | 🔵 Roadmap | — |

## Reports

- **[2026-06-28 — Slither static analysis (GBLIN V6)](./2026-06-28_slither_GBLIN_V6.md)** — automated static analysis with Slither 0.11.5 on the production V6 contract. **Result: no critical or high-severity vulnerabilities.** Every high-severity flag is either a known OpenZeppelin false positive or fully mitigated by the contract's `ReentrancyGuard` and trusted-token assumptions. Full reproduction steps included.

*No paid third-party audit has been commissioned yet — by choice, GBLIN V6 is fully open and verifiable for everyone. The contract source is publicly verified on BaseScan and the automated security baseline above is published in full. Independent reviews and PRs are welcome.*

When formal external audits are completed, reports will be added here as PDFs:

```
audits/
├── README.md                                # this file
├── 2026-06-28_slither_GBLIN_V6.md           # automated static analysis (Slither)
├── 2026-XX-XX_<auditor>_GBLIN_V6.pdf        # planned external audit
└── ...
```

## Public Verification

- **BaseScan**: [`0x36C81d7E1966310F305eA637e761Cf77F90852f0`](https://basescan.org/address/0x36C81d7E1966310F305eA637e761Cf77F90852f0)
- **Source**: [GBLIN_V6.sol](../GBLIN_V6.sol)

## Reporting Issues

For security vulnerabilities, see [SECURITY.md](../SECURITY.md).
