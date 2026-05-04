# Security Policy

## Reporting a Vulnerability

The GBLIN Protocol team takes security issues seriously. We appreciate your efforts to responsibly disclose your findings.

### Where to report

- **Email**: `info@gblin.digital` (use PGP if possible)
- **Subject prefix**: `[SECURITY]`

**Please do NOT report security vulnerabilities through public GitHub issues.**

### What to include

1. Type of issue (e.g. reentrancy, oracle manipulation, access control bypass).
2. Full path of the affected source file(s).
3. Location in the file (line numbers, function name).
4. Step-by-step reproduction or proof-of-concept code.
5. Impact assessment (loss of funds, DoS, data leak).
6. Suggested fix (if any).

### Response timeline

| Stage | Target time |
|---|---|
| Acknowledgement of report | 48 hours |
| Initial assessment | 5 business days |
| Patch and disclosure plan | 30 days |
| Public disclosure | 90 days max (negotiable) |

## Severity Classification

| Severity | Examples |
|---|---|
| **Critical** | Direct theft of user funds, contract takeover, oracle bypass |
| **High** | Permanent freezing of funds, governance bypass, reentrancy with profit |
| **Medium** | Temporary DoS, NAV miscalculation under specific conditions |
| **Low** | Gas inefficiencies, missing event emissions, minor logic bugs |

## Bug Bounty

GBLIN Protocol is committed to running a bug bounty program. Researchers acting in good faith will:

- Not face legal action.
- Be acknowledged in protocol release notes.
- Be eligible for monetary rewards (program details forthcoming).

## Out of Scope

- Issues already reported.
- Vulnerabilities in dependencies (OpenZeppelin, Chainlink, Uniswap V3) — please report directly to those maintainers.
- Issues requiring physical access to a user's device.
- Social engineering attacks.

## Supported Versions

| Version | Supported |
|---|---|
| V5 (current) | ✅ |
| V4 | ❌ |
| V3 | ❌ |

Only the latest deployed version receives security updates.
