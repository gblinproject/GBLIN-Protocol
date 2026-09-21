# Security reviews and test campaigns

This directory records what has been done to check the GBLIN contracts, and what has not.

## Status

| Stage | Vault in service (`0xc2181d97…1D53`) | Previous contract (`0x36C81d7E…52f0`) |
|---|---|---|
| Public source verification | Sourcify full match and Basescan | Basescan |
| Line-by-line review | The maintainer, and three AI systems with reproducible reading tests (below) | The maintainer |
| Static analysis | Slither and Aderyn; every reported item read individually, none accepted as a defect | Slither: [report](./2026-06-28_slither_GBLIN_V6.md), 0 critical / 0 high |
| Unit and fuzz tests | 537 tests, fuzzing at 20,000 runs | — |
| Invariant tests | 13 invariants, 1,000,000 operations each | — |
| Fork tests against the live pools and feeds | 132 tests at Base block 51,340,251, including attack scenarios: inflation, reentrancy, sandwiches on the auction, feed drift, token blacklists, dust | — |
| Coverage-guided fuzzing (Medusa) | 6 hours, 624,814 calls, 66,252 branches, 46 properties, 0 failures | — |
| Mutation testing (slither-mutate), `GBLIN` and the first fill agent | Partial, stopped at a time cap: 261 mutants caught, 6 not caught by the suite frozen at the start of the campaign, 349 not compiling. The six are listed below | — |
| Symbolic execution (Halmos) | 12 properties: 3 proved, 9 undecided within the solver budget, 0 counterexamples | — |
| Scale simulation on a fork | 10 scales from 10 dollars to 10 billion: every exit paid within 7 bps of NAV up to 100,000 dollars; from 100 million a 10-million exit is refused whole and the shares stay with the holder | — |
| Paid third-party audit | none | none |
| Formal verification | none | none |

The unit, fuzz, invariant and fork suites are internal and not published in this repository yet.

### Fill agent and order generator

`GblinAuctionOrder` and the current `CowFillAgent` were added after the launch and did not go through every campaign above.

| Stage | Result |
|---|---|
| Public source verification | Sourcify full match and Basescan, both contracts |
| Unit and fuzz tests | 21 tests on the fill path against a settlement and a `ComposableCoW` that follow the deployed contracts step by step, fuzzing at 20,000 runs: fill at the auction size and price, surplus to the vault, partial fills, both sides, every rejection code of `verify`, a half-done swap that locks the vault, the emergency close, a token that refuses the return |
| Invariant tests | The vault's 13 invariants, 1,000,000 operations each, with solver fills among the operations |
| Fork tests against the live contracts | 6 tests on Base with CoW Protocol's settlement and `ComposableCoW`: fills at market, a price below the auction refused by the real settlement, a half-done settlement that cannot touch the vault, no signature without an auction, the whole gap closed by successive settlements, and the order and signature produced by `ComposableCoW` itself accepted by the settlement, including an order cut at the start of a bucket and settled at its end |
| Deployment rehearsal on a fork | The full sequence — deploy, connect, register — run against a copy of Base before the real one, with every immutable read back |
| Static analysis | Slither, medium and high: four classes reported — modulo arithmetic flagged as weak randomness (the bucket computation), division before multiplication, strict equalities, unused return values — each read; none is a defect |
| Coverage-guided fuzzing, mutation testing, symbolic execution | not run on these two contracts |
| Line-by-line review by the AI reviewers | not run on these two contracts |

### Mutants not caught

A surviving mutant marks a path the frozen suite did not exercise, not a defect in the code. The six are: two constructor lines (the initial `lastVolRefresh` and the `OwnershipTransferred` event), the early return of `_inKindFeeBps` on an empty vault, the early return of `_worstDrift` on an empty vault, the `continue` on an empty row in `_isStale`, and the token transfer inside the `(v, r, s)` form of `receiveWithAuthorization`. They are test gaps to close.

## How the AI reviews were run

Each reviewer received a numbered listing of the sources, a closed perimeter of functions and a reading test whose answers are not in the file. A finding counted only when the reviewer printed its citation from the file and the citation matched the source line for line; every citation was checked by hand. Two real defects came out of these rounds and were fixed before deployment. A fourth system was tried and dropped: it invented line numbers in every round.

"Undecided" in the Halmos row means what it says: the properties were neither proved false nor proved true within the solver's time budget.

## What this is not

None of the above is an audit in the sense the word is used by audit firms, and the protocol does not describe itself as audited. The reviews were made by the people who wrote the code and by tools that can be wrong. The bounds that hold regardless of review are in the code and listed in [`docs/governance.md`](../docs/governance.md).

## Reporting

For vulnerabilities, see [`SECURITY.md`](../SECURITY.md). Findings reported so far and their status: [`KNOWN_ISSUES.md`](../KNOWN_ISSUES.md).
