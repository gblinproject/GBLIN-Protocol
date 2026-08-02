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

## Recognition and rewards

**There is no monetary bug bounty at present, and we would rather say so plainly than leave the question
open.** The protocol holds roughly one thousand dollars of total value and is self-funded; a reward pool
would have to come out of the same money that pays for an external audit, which we consider the higher
priority.

Researchers acting in good faith will:

- Not face legal action.
- Be credited by name, or by handle if preferred, in `KNOWN_ISSUES.md` and in the release notes of any
  change that results from the report — whether or not we agree with the reported severity.
- Have their finding recorded even when we dispute it, with our reasoning published alongside, so that
  disagreements are visible rather than buried in a private thread.

If external funding arrives, a monetary program is the second item it pays for, after an external audit,
and this section will be updated before any such program is announced anywhere else.

## Out of Scope

- Issues already reported. **See [`KNOWN_ISSUES.md`](KNOWN_ISSUES.md)** for the full list of findings
  reported so far, what we verified, and where each one stands — please check it before writing up.
- Vulnerabilities in dependencies (OpenZeppelin, Chainlink, Uniswap V3) — please report directly to those maintainers.
- Issues requiring physical access to a user's device.
- Social engineering attacks.

## Supported Versions

| Version | Supported |
|---|---|
| V6 (current — `0x36C81d7E1966310F305eA637e761Cf77F90852f0`) | ✅ |
| V5 (deprecated 2026-06) | ❌ |
| V4 | ❌ |
| V3 | ❌ |

Only the latest deployed version receives security updates.
