# BEAT OUR SHIELD — Season 1
**The first open competition to tune a live mainnet protocol.**

GBLIN's Crash Shield is an autonomous risk policy running on Base mainnet (it [provably fired](https://basescan.org/tx/0x896be221989930776972c78f81e2be9081c90d0027c14f7cd74bf51b9ad0acca) on June 5, 2026, cutting WETH exposure 45%→9% with no human in the loop). Its parameters are governed by a 48h public timelock.

**We are opening those parameters to the world.** Find a configuration that beats ours in the official backtest, and — if it passes the published robustness check — we schedule **your parameters** on the live mainnet contract via the timelock, with **your name (or your agent's ERC-8004 id) credited forever** in the protocol CHANGELOG and on gblin.digital.

No token purchase required. No fees. Nothing to buy. This is a competition of intelligence, human or machine.

## The numbers to beat
| Config (full / slash / slow) | Final on $10k (10.1y) | MaxDD | **Score (Calmar)** |
|---|---|---|---|
| Current on-chain: 3000 / 2000 / 15 | $1,546,640 | -50.30% | 1.2874 |
| **Best known (our sweep): 2500 / 2000 / 15** | $1,553,094 | -46.58% | **1.3915** |
| Unshielded 45/45/10 basket | $1,629,256 | -84.66% | 0.77 |

**Win condition: Score > 1.3915.**

## How to play (2 minutes, or 2 lines of code for an agent)
```bash
git clone https://github.com/gblinproject/GBLIN-Protocol
cd GBLIN-Protocol/challenge
python3 score.py <fullSlashDrawdownBps> <slashMultiplier> <slowPeakDecayPerDayBps>
# example: python3 score.py 2500 2000 15
```
The scorer is an exact replica of the on-chain `refreshWeights()` logic, run on 10.1 years of real BTC/ETH daily history (2016-05-18 → 2026-06-24, included in `prices.csv`). Deterministic: same input, same score, verifiable by anyone.

**Allowed bounds** (what the timelock can actually set): `full` 2000–9000 · `slash` 500–5000 · `slow` 1–50.

## How to submit
Open a **GitHub issue** on this repo titled `[SHIELD] full=X slash=Y slow=Z` and paste the full output of `score.py`. One entry per issue; unlimited entries. AI agents welcome — include your ERC-8004 agentId if you have one.

**Season 1 closes: August 1, 2026, 23:59 UTC.**

## How the winner is decided (published, deterministic)
1. Highest **Score** among valid submissions, IF
2. it passes the robustness check: beats the current on-chain config in **≥55% of 150 block-bootstrap synthetic histories** (script and seed published at season close — same methodology as [our published simulation report](../..)).
This guards against overfitting the single historical path. If no submission passes, the best-known config wins and we say so.

## The prize (what money can't buy)
- Your parameters **scheduled on the live mainnet contract** via the 48h public timelock (execution tx = your proof, forever).
- Permanent credit in [CHANGELOG.md](../CHANGELOG.md) and on gblin.digital.
- An ERC-8004 reputation entry for your agent (once our reputation writer ships): "improved a live mainnet protocol, evidence attached."

## Honest notes
- The backtest measures the past; it is not a promise about the future. The robustness check reduces, not eliminates, overfitting risk.
- The final scheduling decision passes through the same 48h timelock as every parameter change — the delay and a human veto are part of the protocol's constitution.
- GBLIN is volatile crypto exposure with a defensive policy — not a stablecoin, not financial advice.

Questions: open an issue, or find us — Farcaster [@gblin](https://warpcast.com/gblin) · X [@GBLIN_Protocol](https://x.com/GBLIN_Protocol) · info@gblin.digital
