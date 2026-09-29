# Security reviews and test campaigns

This directory records what has been done to check the GBLIN contracts, and what has not.

## Status

| Stage | Vault in service (`0xc2181d97…1D53`) | Previous contract (`0x36C81d7E…52f0`) |
|---|---|---|
| Public source verification | Sourcify full match and Basescan | Basescan |
| Line-by-line review | The maintainer, and three AI systems with reproducible reading tests (below) | The maintainer |
| Static analysis | Slither and Aderyn; every reported item read individually, none accepted as a defect | Slither: [report](./2026-06-28_slither_GBLIN_V6.md), 0 critical / 0 high |
| Unit and fuzz tests | 591 tests in the internal suite, the 57 of the fill agent below included; fuzzing at 20,000 runs | — |
| Invariant tests | 13 invariants, 1,000,000 operations each | — |
| Fork tests against the live pools and feeds | 132 tests at Base block 51,340,251, including attack scenarios: inflation, reentrancy, sandwiches on the auction, feed drift, token blacklists, dust | — |
| Coverage-guided fuzzing (Medusa) | 6 hours, 624,814 calls, 66,252 branches, 46 properties, 0 failures | — |
| Mutation testing (slither-mutate), `GBLIN` and the first fill agent | Partial, stopped at a time cap: 261 mutants caught, 6 not caught by the suite frozen at the start of the campaign, 349 not compiling. The six have since been settled (below) | — |
| Symbolic execution (Halmos) | 12 properties: 3 proved, 9 undecided within the solver budget, 0 counterexamples | — |
| Scale simulation on a fork | 10 scales from 10 dollars to 10 billion: every exit paid within 7 bps of NAV up to 100,000 dollars; from 100 million a 10-million exit is refused whole and the shares stay with the holder | — |
| Paid third-party audit | none | none |
| Formal verification | none | none |

The unit, fuzz, invariant and fork suites are internal and not published in this repository yet.

### Fill agent and order generator

`GblinAuctionOrder` and the current `CowFillAgent` were added after the launch. The campaigns below were run on their deployed source.

| Stage | Result |
|---|---|
| Public source verification | Sourcify full match and Basescan, both contracts |
| Unit and fuzz tests | 57 tests, fuzzing at 20,000 runs. 21 on the fill path against a settlement and a `ComposableCoW` that follow the deployed contracts step by step: fill at the auction size and price, surplus to the vault, partial fills, both sides, every rejection code of `verify`, a half-done swap that locks the vault, the emergency close, a token that refuses the return. 20 on the order generator called the way CoW Protocol's watch-tower calls it: the order cut on both sides equal to `bid` in size and price, including when the vault's WETH limits it, and every polling signal. 11 on the agent alone against a stand-in vault, branch by branch: opening, registration and removal by the owner only, swap-in-progress, returned values and events of both closes, a token that answers `false`. 5 on the bucket arithmetic: exact values along the curve and two fuzz properties |
| Invariant tests | The vault's 13 invariants, 1,000,000 operations each, with solver fills among the operations |
| Fork tests against the live contracts | 6 tests on Base with CoW Protocol's settlement and `ComposableCoW`: fills at market, a price below the auction refused by the real settlement, a half-done settlement that cannot touch the vault, no signature without an auction, the whole gap closed by successive settlements, and the order and signature produced by `ComposableCoW` itself accepted by the settlement, including an order cut at the start of a bucket and settled at its end |
| Deployment rehearsal on a fork | The full sequence — deploy, connect, register — run against a copy of Base before the real one, with every immutable read back |
| Static analysis | Slither, medium and high: four classes reported — modulo arithmetic flagged as weak randomness (the bucket computation), division before multiplication, strict equalities, unused return values — each read; none is a defect |
| Coverage-guided fuzzing (Medusa) | 6 hours, 519,500 calls, 46 properties, 0 failures; 10,435 solver fills completed through the agent and the generator's `verify`. Order cutting (`getTradeableOrder`), the emergency close and order registration were not part of this campaign; the unit tests cover them. Medusa's line-coverage report does not map these contracts (it shows zero lines for the vault as well), so coverage is taken from the harness, not from the report |
| Mutation testing (slither-mutate) | 384 mutants of the two contracts. 182 caught by the suite of the time; the 202 survivors marked paths that suite did not exercise, tests were added for them and every survivor was run again, one at a time, against the unchanged source: 182 more caught, 20 equivalent (below). None left unexplained |
| Symbolic execution (Halmos) | 9 properties, order amounts restricted to 128 bits: 7 proved, 2 undecided within 30 minutes each, 0 counterexamples. Proved: only the vault opens or closes a fill; only the vault's owner registers or removes an order; `verify` accepts an order only at the auction price or better, only in the block of the open fill, only with the fill's tokens, no fee, the agent as receiver, ERC-20 balances and a registered app data; the emergency close never runs in the fill's block, and afterwards anyone can run it, it clears the state and returns everything to the vault; outside its block a fill never reads as a swap in progress; a close with no swap returns the whole output. Undecided: the two bounds of the bucket computation, which is not linear; they are checked by fuzzing and by exact-value tests instead |
| Line-by-line review by the AI reviewers | Grok 4 (Expert) and ChatGPT (Thinking), on a numbered listing of the two contracts together with every file they depend on — vault, Lens, libraries, CoW Protocol interfaces — and a closed perimeter of 30 functions, after a file-integrity check and a reading test that both answered correctly. Grok covered the 30 functions, with 177 of 178 citations exact and the wrong one corrected by the reviewer in the following line; ChatGPT covered the 30 functions too, citing code by statement for the first 17 and by line for the other 13, with 229 of 229 line citations exact. No defect with a loss scenario. Raised and checked: the constructors do not validate the addresses they receive (the deployed values were read back on Base and match the vault in service, its Lens, CoW Protocol's settlement and `ComposableCoW`); the Lens computes the gap with unfiltered prices and the generator reads token decimals live, so an order could differ in size from `bid` — `verify` still holds the price of the fill, and the generator refuses a stale or out-of-bounds feed before cutting an order |

### Mutants not caught

A surviving mutant marks a path the suite did not exercise, not a defect in the code.

**Vault.** Six mutants survived the suite frozen at the start of the campaign. Four are now caught by tests, each checked to fail against its mutant: the two constructor lines (the initial `lastVolRefresh` and the `OwnershipTransferred` event), the `continue` on an empty row in `_isStale`, and the token transfer inside the `(v, r, s)` form of `receiveWithAuthorization`. The other two, the early returns of `_inKindFeeBps` and `_worstDrift` on an empty vault, are equivalent: the vault never reaches zero value, because the virtual shares always leave a residue.

**Fill agent and order generator.** The 20 mutants no test can catch change nothing reachable:

- seven store a constant differently (as an immutable, or in a narrower type);
- six rewrite a comparison that cannot land on the other side: four on unsigned integers (`> 0` for `!= 0`, `<= 0` for `== 0`), two against a block number or a timestamp that never exceeds the current one;
- two lengthen the feed age allowed in conversions, which never binds because a stricter age is checked first (at most six hours, 26 hours for stable feeds);
- one rewrites the staleness condition into a logically identical form;
- one drops the length check before reading a revert selector; the conversion pads a short reason with zeros either way;
- one drops the guard on WETH held minus WETH reserved; where it could matter, the watch-tower receives the same "try next block" signal with a different reason text;
- one lowers the amount the agent asks from `bid` from 2^256 − 1 to 2^128 − 1; the vault cuts the offer to the gap and refuses a fill above 2^128 − 1, so both ask for the same fill;
- one passes `tx.origin` instead of `msg.sender` as the sender given to `ComposableCoW`; with no swap guard set, nothing reads it.

## How the AI reviews were run

Each reviewer received a numbered listing of the sources, a closed perimeter of functions and a reading test whose answers are not in the file. A finding counted only when the reviewer printed its citation from the file and the citation matched the source line for line; every citation was checked by hand. Two real defects came out of these rounds and were fixed before deployment. A fourth system was tried and dropped: it invented line numbers in every round.

"Undecided" in the Halmos row means what it says: the properties were neither proved false nor proved true within the solver's time budget.

## What this is not

None of the above is an audit in the sense the word is used by audit firms, and the protocol does not describe itself as audited. The reviews were made by the people who wrote the code and by tools that can be wrong. The bounds that hold regardless of review are in the code and listed in [`docs/governance.md`](../docs/governance.md).

## Reporting

For vulnerabilities, see [`SECURITY.md`](../SECURITY.md). Findings reported so far and their status: [`KNOWN_ISSUES.md`](../KNOWN_ISSUES.md).
