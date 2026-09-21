# Changelog

All notable changes to the GBLIN Protocol will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Fill agent] — 2026-09-21

`GblinAuctionOrder` `0x156Ffd19819e02d9809cED8fa1416EDCD31ddaB9` and `CowFillAgent` `0x0f4307A5Eb7D33d04Cb68fb0bA4d47a56C7E2fc8` deployed on Base, and the agent set as the vault's
fill agent. The vault itself is unchanged.

### Added
- The auction can be filled by CoW Protocol solvers. The agent owns one conditional order per auctioned row on
  `ComposableCoW` (cbBTC and USDC), with `GblinAuctionOrder` as handler; CoW Protocol's watch-tower posts the
  discrete orders, and a solver settles each one with a pre-hook that opens the fill and a post-hook that closes it.
- `CowFillAgent.register` and `unregister`, callable only by the vault's owner.

### Changed
- The agent's EIP-1271 signature is the `ComposableCoW` payload; order checks moved into the handler's `verify`,
  which also requires the order's `appData` to be one of the two registered for its row.

### Deprecated
- The first fill agent, `0xb78d74642E32e86D1d96330D047C6245a2bA7D5E`, deployed with the vault and never connected.

## [Vault in service] — 2026-09-20

New deployment on Base: `GBLIN` `0xc2181d975c05c8c724b334bcED0764c0b86B1D53` with `GBLINLens`, `GBLINZap`,
`SequencerSentinel`, `UniswapV3Adapter` and a first `CowFillAgent`, left disconnected and later superseded. Solidity 0.8.37. Sources in `src/`.

### Changed
- Shares are minted at NAV and redeemed pro rata in kind; the vault never swaps. Entering with any token and
  exiting to ETH go through `GBLINZap`, all or nothing.
- Rebalancing is a Dutch auction (`bid`) at the oracle price adjusted by a premium; there is no bounty and no
  stability fund. Anyone can fill it.
- Fees: 0.05% protocol and 0.05% stability on mints with ETH or WETH; an in-kind floor of 0.50% plus a deviation
  tax; a 0.50% yearly management fee. All fees to the protocol are minted as shares. No fee on redemption.
- Payments by signature (EIP-3009) with `(v, r, s)` and bytes signatures; `eip712Domain()` (EIP-5267).
- Ownership in two steps (`transferOwnership`, `acceptOwnership`); no `renounceOwnership`.
- A leg that cannot be delivered on redemption is credited and claimed with `claimPending`; transfers on the
  way out run under a gas cap.
- Assets can be delisted, relisted and abandoned; listing requires a probe deposit and stores the decimals.
- The sequencer sentinel lets a guardian pause mints and fills for a bounded stretch; redemptions are never paused.

### Security
- Addressed every finding recorded in `KNOWN_ISSUES.md` against the previous contract; the status of each on
  this deployment is in its section "Status on the vault in service". In particular the exit to ETH no longer
  dispatches a swap with a zero minimum for a leg it cannot price (§5): it is all or nothing in `GBLINZap`,
  under the caller's minimum and a NAV-based bound. The sell cooldown is written only for a minter who receives
  its own shares (§6); a transfer still bypasses it, by design, and the round trip costs the mint fees.

## [Challenge] — 2026-07-27

### Changed
- "Beat Our Shield" Season 1 deadline extended from 2026-08-01 to **2026-09-30** (announced 2026-07-27, before the original close). Scoring rules, allowed bounds and the robustness criterion are unchanged.

## [V6] — 2026-06 — Production
Contract: `0x36C81d7E1966310F305eA637e761Cf77F90852f0` (Base) · Owner: `GblinTimelockController` 48h `0x6aBeC8716fFeEcf7C3D6e68255b4797113E8e5Dd`

### Added
- Adaptive dual-peak Crash Shield: fast + slow structural peak, proportional slash with hysteresis (replaces the binary 20% trigger).
- `buyGBLINInKind(token, amount, minOut)` — single-asset in-kind purchase.
- Governance setters within immutable hard caps (each fee ≤5%, slippage ≤20%, crash bounds 3–90%), all behind the 48h timelock.
- Adaptive internal slippage envelope (0.5%–5.5%) driven by on-chain volatility; oracle re-point with 25% deviation guard and decimals check; settable swap router and per-asset pool fee; bounded adaptive keeper bounty with `bountyInterval`.

### Changed
- Fees/parameters now governance-settable (defaults 0.05% + 0.05%); `minDeposit` 0; sell cooldown 20s (was 2 min).
- Weekly yield drip replaced by instant `_splitFee` on every buy.
- JIT redemption is a deterministic two-step flow (`sellGBLINForEth` + WETH→USDC swap).
- `sellGBLIN` (in-kind pro-rata exit) no longer depends on oracles or the sequencer feed.

### Removed
- `renounceOwnership` (by design: the owner is the 48h timelock, un-ruggable but adaptable).
- `sellGBLINForToken`, `mintInKind`/`redeemInKind` (superseded by `buyGBLINInKind`), weekly drip.

### Governance log (on-chain)
- 2026-06-24 — `setShieldCurve(15, 3000)` — tx `0xde3402538426161dbf8a0b62b234e14a0e0882c923a0ff56efe957a3e8dda385`
- 2026-06-27 — ownership → timelock — tx `0xeec950b8896e6285eea7d1f66918a13ddf52ff8a0f4b439bf2a3ee79fcff54a6`
- 2026-07-16 — `setOracleTimeout(90000)` scheduled (48h delay, executable 2026-07-18)

## [V5] — 2026-04-03

### Added
- `sellGBLIN(uint256)` — burn-and-distribute basket assets natively.
- `sellGBLINForToken(uint256, address, uint24, uint256)` — sell GBLIN for any ERC-20.
- `quoteMintInKind(uint256)` and `mintInKind(uint256)` — institutional in-kind facility.
- `redeemInKind(uint256)` — pro-rata basket redemption with zero swap.
- 48-hour timelock governance for asset proposal/execution.
- `updateMaxSlippage(uint256)` and reserve/oracle admin updates.

### Changed
- Migrated frontend contract address from V4 (`0xED334B...0a50`) to V5 (`0x38DcDB...6345`).
- Refined NAV anti-dilution snapshot logic.
- Improved Crash Shield redistribution priority (stables first).

### Security
- Strengthened oracle timeout handling.
- Added asset amputation logic for dead oracles.

## [V4] — Deprecated

Frontend reference: `0xED334B4CDaFCAe6D42bb9A57DE565fD3e9640a50`

## [V3] — Deprecated

## [V2] — Deprecated

## [V1] — Initial Fair Launch
