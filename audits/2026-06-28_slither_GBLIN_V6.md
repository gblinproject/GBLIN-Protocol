# Slither Static Analysis — GBLIN V6

| Field | Value |
|---|---|
| **Contract** | `GBLIN_GlobalBalancedLiquidityIndex` (GBLIN V6) |
| **Address (Base mainnet)** | [`0x36C81d7E1966310F305eA637e761Cf77F90852f0`](https://basescan.org/address/0x36C81d7E1966310F305eA637e761Cf77F90852f0) |
| **Tool** | [Slither](https://github.com/crytic/slither) `0.11.5` |
| **Compiler** | solc `0.8.20` (viaIR + optimizer) |
| **Dependencies** | OpenZeppelin Contracts `5.0.2`, Chainlink Contracts |
| **Date** | 2026-06-28 |
| **Result** | **No critical or high-severity vulnerabilities.** |

## Verdict

Slither produced **190 findings across 101 detectors**. After manual review, **none represent a real critical or high-severity vulnerability.** Every high-severity flag is either a well-known OpenZeppelin false positive or is fully mitigated by the contract's `ReentrancyGuard` and trusted-token / trusted-wallet assumptions.

> One-line summary: *Slither static analysis — no critical/high issues; all high-severity flags are either OpenZeppelin false positives or mitigated by ReentrancyGuard and trusted-token assumptions.*

## Summary table

| Detector | Count | Severity | Real impact |
|---|---|---|---|
| incorrect-exp | 1 | High | **None** — false positive inside OZ `Math.mulDiv` (intentional XOR in the Newton seed). |
| reentrancy-balance | 3 | High | **None** — functions are `nonReentrant`; external calls go to trusted tokens / Uniswap router. |
| reentrancy-eth | 3 | High | **None** — `nonReentrant` guard; `founderWallet` is protocol-owned and trusted. |
| divide-before-multiply | 13 | Medium | Mostly OZ `Math`; GBLIN cases are acceptable micro-precision (decay / decimal scaling). |
| incorrect-equality | 20 | Medium | **By design** — `price == 0` / `supply == 0` null-checks, not balance equality. |
| reentrancy-no-eth | 1 | Medium | **None** — `nonReentrant`; basket tokens (cbBTC/WETH/USDC) have no transfer callbacks. |
| uninitialized-local | 1 | Medium | **By design** — `sev` defaults to 0 → zero slash, the intended behaviour. |
| unused-return | 5 | Medium | **By design** — return values intentionally ignored (balance-diff pattern; try/catch redemption). |
| shadowing-local | 1 | Low | OZ `ERC20Permit` constructor param. Cosmetic. |
| calls-loop | 42 | Low | Oracle/balance reads over a 3-asset basket (governance-bounded to 50). Acceptable. |
| reentrancy-benign | 5 | Low | Guard-protected; no exploitable ordering. |
| timestamp | 27 | Low | Standard `block.timestamp` comparisons (cooldowns/decay windows). Acceptable. |
| assembly / pragma / cyclomatic / dead-code / solc-version / low-level-calls / naming / too-many-digits | ~50 | Informational | Library code + style. No security impact. |
| cache-array-length / constable-states | 13 | Optimization | Gas micro-optimizations only. |

## Manually verified findings

- **`uninitialized-local` — `refreshWeights().sev` (L595).** If `sev` stays 0, `keepBps` resolves to 100% → `newWeight == baseWeight` → zero slash. The default-0 path is exactly the intended "no cut" behaviour. **Not a bug.**
- **`unused-return` / `redundant-statements` — `sellGBLIN` (L511).** The asset transfer is wrapped in `try/catch` on purpose so a single misbehaving token cannot brick a full in-kind redemption; the `ok2;` line is only cosmetic. **Not a bug.**
- **`reentrancy-*` (High).** All entry points carry `nonReentrant`; the external calls target cbBTC/WETH/USDC, the Uniswap V3 router and the protocol's own `founderWallet`. No untrusted callback surface. **Mitigated.**

## Hygiene notes (non-blocking, for a future V7)

These are best-practice improvements only — **no action is required or possible on the live contract**, which is immutable (no proxy) and owned by a 48h Timelock Controller:

- Apply strict checks-effects-interactions in `_mintGBLIN` / `incentivizedRebalance` (write state before external calls) as defense-in-depth, even though `nonReentrant` already covers it.
- Scale before dividing in `_convertToEth` / `_convertEthToAsset` to shave residual precision loss.
- Use `SafeERC20` for the in-kind transfer in `sellGBLIN` for consistency with the rest of the contract.

## How to reproduce

```bash
npm install @openzeppelin/contracts@5.0.2 @chainlink/contracts
solc-select use 0.8.20
slither GBLIN_V6.sol \
  --solc-remaps "@openzeppelin=node_modules/@openzeppelin @chainlink=node_modules/@chainlink" \
  --solc-args "--optimize --via-ir" \
  --checklist
```

## Disclaimer

Slither is an automated static-analysis baseline, **not** a substitute for a manual external audit or formal verification. It is published here in the spirit of full transparency. The GBLIN source is publicly verified on BaseScan and open for independent review.
