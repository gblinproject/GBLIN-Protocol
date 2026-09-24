# Governance

GBLIN has no governance token, no vote and no off-chain proposal system. The vault has one owner, a 48-hour timelock, and every owner action is bounded in code. Trust rests on two things that hold for the life of the vault: the delay, which gives holders time to leave before any change lands, and the bounds, which no change can exceed.

## Roles

| Role | Address | Powers |
|---|---|---|
| Owner (timelock, `0x6aBeC8716fFeEcf7C3D6e68255b4797113E8e5Dd`, since 2026-09-22) | 48-hour delay, 14-day grace, open executor | Parameters, addresses, base weights, asset listing and delisting, ownership transfer |
| Proposer on the timelock | `0x9FFa542E369C53af62380296092EC669f329a9ee` | Schedules operations |
| Canceller on the timelock | `0x30590c0D05c26562d7296CE3D927d3418d2e6dcA` | Cancels scheduled operations |
| Fee recipient | `0x9FFa542E369C53af62380296092EC669f329a9ee` | Receives the protocol and management fees as shares; changed only by the owner |
| Sentinel guardian | `0x30590c0D05c26562d7296CE3D927d3418d2e6dcA` | Reports the sequencer down for a bounded stretch |

The vault and the sentinel have been owned by the timelock since 2026-09-22, when the scheduled `acceptOwnership` operations executed; the state is public through `owner()` and `pendingOwner()`, and through `get_governance_state` in the MCP server.

## What the owner can do, and within what bounds

### `setParam(key, values)`

| Key | Group | Bounds enforced in code |
|---|---|---|
| 2 | Crash shield: base threshold, volatility multiplier, recovery band, slash multiplier | threshold above zero and below the full-slash drawdown; multiplier ≤ 100000; band below the minimum crash threshold; slash ≤ 10000 |
| 3 | Mint fees: protocol, stability | sum ≤ 100 bps; protocol ≤ in-kind floor |
| 4 | Auction: start discount, cap, ramp | 1–300 bps; ≤ 300 bps; 1 minute to 30 days |
| 5 | Minimum deposit | ≤ 10 ETH |
| 6 | Feed ages: pricing, trading | 10 minutes to 6 hours; 1 minute to the pricing age |
| 7 | Peg band of stable assets | ≤ 1000 bps |
| 8 | Auction band: opening threshold, closing threshold | 1–10000 bps; closing below opening |
| 9 | Shield curve: slow peak decay per day, full-slash drawdown | ≤ 10000; above the minimum crash and the base threshold |
| 11 | Shield tuning: minimum crash, maximum crash, fast peak decay per day, volatility update interval | minimum above the recovery band and below the full-slash drawdown, at most the maximum; maximum and decay ≤ 10000; interval 1 second to 30 days |
| 13 | In-kind fee: floor, deviation tax | protocol fee to 300 bps; ≤ 500 bps |
| 14 | Redemption cooldown | ≤ 1 hour |
| 16 | Basket size cap | current length to 50 |
| 17 | Listing delay | ≤ 30 days |
| 19 | Management fee per year | ≤ 200 bps; the fee accrued so far is minted at the previous rate first |

Every value of a group is written at once; unused values must be zero; any other key reverts. `ParamUpdated` is emitted.

### `setAddress(key, address)`

| Key | Address | Constraint |
|---|---|---|
| 2 | Sequencer feed | Must have code, or be zero |
| 3 | Fee recipient | Cannot be zero; the management fee accrued so far is minted to the current recipient first |
| 5 | ETH price feed | Same decimals and declared identity as the current feed, answering with a live price |
| 6 | Fill agent | Must have code or be zero; cannot be the vault; changing it closes an open fill first |

### Basket

- `setBaseWeights(weights)`: one weight per row, sum at most 10000, zero for delisted rows.
- `proposeAsset(token, oracle, isStable, baseWeight)`, with a base weight of at most 30%, then, after the listing delay, `executeAssetAddition(probe)`: the probe is pulled from the caller and must arrive in full, which rejects tokens that take a cut on transfer and keeps the vault from ever being empty. Decimals are read once and stored.
- `assetAction(k, i)`: delist (1) sets the weights to zero and keeps the row in the NAV, to be sold through the auction; relist (2) reopens a delisted row with zero weight; abandon (3) quarantines a delisted row forever; it requires a feed that has given no price for seven days and refuses to leave the vault without a positive NAV, so that tokens sent to a dead row cannot keep it in the basket. The timelock's delay gives holders the time to redeem the row in kind first.

### Ownership

`transferOwnership(newOwner)` sets a pending owner; the transfer completes only when the pending owner calls `acceptOwnership`. The zero address cancels a pending transfer. There is no `renounceOwnership`: a vault without an owner could not repoint a failing feed.

## What the owner cannot do

- Move holders' assets, mint shares to any address other than the fee recipient through the fee mechanism, or take assets out of the reserves.
- Exceed any bound above.
- Pause redemption in kind, which reads no feed and is not gated by the sentinel.
- Upgrade the code: there is no proxy.
- Act without the delay: every owner call is a scheduled operation, and the schedule is public on the timelock before it lands.

## Listing rule

An asset is listed only if it delivers the whole amount it is asked to transfer, without a fee or a reduction, for as long as it stays in the basket. Redemption relies on it: the vault trusts a token's `transfer` return value on the way out rather than re-reading balances, so that the call that must always succeed has no new way to fail.
