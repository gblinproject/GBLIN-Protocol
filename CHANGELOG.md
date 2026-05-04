# Changelog

All notable changes to the GBLIN Protocol will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
