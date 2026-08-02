# Known Issues and Accepted Risks

This page lists every security finding reported to GBLIN Protocol, what we verified, and where each one
stands. It exists so that researchers can see what has already been reported before spending time on it —
`SECURITY.md` places already-reported issues out of scope, and this is the list that statement refers to.

Findings are listed whether or not we agreed with the reporter's severity. Where a reporter corrected us,
that is recorded too.

**Contract status.** The deployed contract is not upgradeable — there is no proxy, and code cannot be
changed in place. Parameters are governance-settable within immutable hard caps, through a 48h timelock
(`0x6aBeC8716fFeEcf7C3D6e68255b4797113E8e5Dd`). This means a code-level fix requires a migration to a new
contract, while a parameter-level mitigation can be applied on the live deployment after the 48h delay.

Last updated: 2026-08-02.

---

## Summary

| # | Reported | Finding | Reporter's severity | Status |
|---|---|---|---|---|
| 1 | 2026-07-07 | Oracle-anchored min-out with no pool price limit on internal swaps | Medium | Accepted as a design observation; severity disputed with measured figures |
| 2 | 2026-07-07 | NAV excludes a delisted asset while redemption pays it pro-rata (previous contract) | Medium | Confirmed; already resolved in the current contract |
| 3 | 2026-07-23 | `buyGBLINInKind` does not collect the stability fee | — | Intentional by design; reporter accepted the explanation |
| 4 | 2026-07-29 | Crash Shield redistributes slashed weight onto already-shielded assets | Medium | Counting logic confirmed; **our first impact assessment was wrong and the reporter corrected it** |
| 5 | 2026-07-31 | Missing slippage floor in `sellGBLINForEth` when a feed is unusable | Low | Reproduced in full; fix planned for the next migration |

---

## 1 — Oracle-anchored min-out, no pool price limit on internal swaps

**Reported by Utkarsh, 2026-07-07.**

Internal Uniswap V3 swaps derive `amountOutMinimum` from the Chainlink price via `_lessSlippage`, and pass
`sqrtPriceLimitX96 = 0`. An oracle-anchored floor does not protect against a pool the caller has just
moved, so the protocol's own swaps are sandwichable — notably in the diversify-on-buy loop, where shares
are minted before the swap, and in `incentivizedRebalance`, which is permissionless.

**Our position.** The mechanism is described correctly. We disagree on severity, for two measured reasons.

First, the 5.5% figure is a ceiling, not the operating tolerance: `_lessSlippage` computes
`minSlippageBps + ewmaVolBps`, and on-chain values at the time of review gave 0.50% for USDC, 1.45% for
cbBTC and 1.76% for WETH. The cap binds only in extreme volatility, where it exists so that defensive
swaps do not revert.

Second, the economics: internal swaps route through cbBTC/WETH and USDC/WETH pools holding millions,
while the protocol's own trades are small. Moving those pools by 1–2% costs far more than the extractable
value.

**Accepted as a legitimate design observation.** Sandwich profitability scales with swap size, so this
becomes material as the vault grows. `maxInternalSlippage` is adjustable through the timelock, and
protected routing is on the list for the next migration.

---

## 2 — NAV excluded a delisted asset while redemption paid it pro-rata

**Reported by Utkarsh, 2026-07-07. Applies to the previous, deprecated contract.**

After `emergencyDelist` zeroed an asset's weight while its balance remained in custody, NAV skipped that
asset (`dynamicWeight > 0` filter) while redemption still paid it out pro-rata. NAV was therefore
understated, and the asymmetry was exploitable as a standing arbitrage.

**Confirmed.** The asymmetry between the two loops is exactly as described. The current contract resolves
it: the NAV loop carries no weight filter. The previous contract is deprecated and out of scope per
`SECURITY.md`.

---

## 3 — `buyGBLINInKind` does not collect the stability fee

**Reported by Deni Roni, 2026-07-23.**

`stabilityFund` is never updated from in-kind deposit volume.

**Intentional by design, not a defect.** `buyGBLINInKind` is the path for depositing the exact basket
directly, with no internal swap and no DEX slippage. Because that path performs no internal swap, the
stability fee is deliberately not split out to the keeper reserve; the deposited value stays in the vault
and accrues to NAV, benefiting every holder pro-rata. The founder fee still applies on this path.

The reporter accepted this explanation. One fair point stands: the `YieldDistributed` event name reads as
a transfer into a separate fund, when the amount represents value accruing to NAV. That is a naming and
documentation matter, noted for a future version.

---

## 4 — Crash Shield redistributes slashed weight onto already-shielded assets

**Reported by Amit Bhakar, 2026-07-29. Reporter's severity: Medium.**

`refreshWeights()` counts eligible recipients of redistributed weight before it resolves which assets are
shielded for that call. Both the recipient count and the recipient selection check asset type and a
nonzero weight, and neither checks the `shielded` flag. A shielded asset can therefore receive weight —
including weight just taken from itself.

**The counting logic is confirmed.** Separating shield-state resolution from recipient selection is an
improvement planned for the next migration.

**Correction to our own first assessment.** Our initial reply characterised the exposure as requiring a
keeper to act. That was wrong, and the reporter was right to challenge it. `refreshWeights()` is a
`public` function with no access control and no cooldown — anyone can call it directly. The weights it
writes persist in storage, and the ordinary deposit path reads them for every purchase above
`diversifyOnBuyThreshold` (0.0005 ETH). Once weights are corrupted, ordinary depositors are affected until
the next refresh, not only whoever triggers a rebalance. We record the correction here rather than leave
the original characterisation standing.

**Precondition, unchanged.** For the shield to engage on an asset its drawdown must exceed the adaptive
threshold, which has a hard floor of 1500 bps. For USDC, whose EWMA volatility sits near zero, that floor
is the effective threshold: USDC would have to trade below roughly $0.85. For calibration, USDC traded
around $0.87 during the March 2023 Silicon Valley Bank episode, and USDT bottomed around $0.95 during the
May 2022 Terra collapse. The reporter's counter-point is fair and worth recording: $0.87 sat about two
percentage points from that threshold, and arrived from a bank failure unrelated to crypto markets.

---

## 5 — Missing slippage floor in `sellGBLINForEth` when a feed is unusable

**Reported by Amit Bhakar, 2026-07-31, with a self-contained Foundry proof of concept. Reporter's
severity: Low.**

When `_convertToEth` cannot produce a usable price, `sellGBLINForEth` still sells the asset and dispatches
the swap with `amountOutMinimum = 0`. The mint path handles the same state correctly, skipping the swap
when the computed floor is zero. `sellGBLINForEth` is also the only one of the three swap sites that does
not check oracle freshness. A related consequence: `quoteSellGBLIN` routes through the same conversion, so
a caller deriving their own `minEthOut` from the contract's quote is not protected in that state.

**Reproduced in full**, 5/5 tests passing, on an unmodified copy of the deployed source under solc 0.8.34
with viaIR and the optimizer at 1 run.

**Preconditions, measured.** `_getOraclePrice` returns zero along three paths: staleness beyond
`oracleTimeout`, a non-positive answer, and a price outside the aggregator's min/max bounds. The bounds
path is not reachable by any realistic price on the live feeds.

For the staleness path, measured on Base on 2026-08-01: ETH/USD and cbBTC/USD update roughly every 21
minutes; USDC/USD runs on a 24-hour heartbeat and, across 108 days of round history (2026-04-15 to
2026-07-31), never exceeded 24.02 hours against an `oracleTimeout` of 25 hours. The state has not occurred.

The non-positive-answer path is independent of the staleness window and has not been tested. The reporter
raised this and it is correctly stated: our measurement bears on one path only.

**What mitigates this today.** The staleness window `oracleTimeout` is governance-settable up to seven
days; widening it reduces how often the state can arise via staleness, at the cost of accepting older
prices in NAV. The in-kind exit `sellGBLIN` touches no oracle and is unaffected. During the Base sequencer
incident of 2026-06-25, the contract's sequencer check reverted transactions for the duration of the
outage and the recovery grace period, and the oracle feeds maintained their normal cadence throughout.

**Fix planned for the next migration**: skip a basket leg that cannot be priced rather than selling it
unfloored, mirroring the guard the mint path already applies. Recorded in `CHANGELOG.md` under
`[Unreleased]`.

---

## Reporting something not on this list

See `SECURITY.md`. Reports that duplicate an entry above are out of scope, but a report that shows an
entry's assessment to be wrong is welcome — item 4 on this page exists in its current form because a
reporter did exactly that.
