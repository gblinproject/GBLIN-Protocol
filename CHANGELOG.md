# Changelog

All notable changes to the GBLIN Protocol will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
