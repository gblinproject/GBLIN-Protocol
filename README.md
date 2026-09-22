# GBLIN — Global Balanced Liquidity Index

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Network: Base](https://img.shields.io/badge/Network-Base%20Mainnet-blue.svg)](https://basescan.org/address/0xc2181d975c05c8c724b334bcED0764c0b86B1D53)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.37-363636.svg)](https://soliditylang.org/)
[![Governance: 48h Timelock](https://img.shields.io/badge/Governance-48h%20Timelock-1f6feb.svg)](https://basescan.org/address/0x6aBeC8716fFeEcf7C3D6e68255b4797113E8e5Dd)
[![npm](https://img.shields.io/npm/v/@gblin-protocol/mcp-server.svg?label=@gblin-protocol/mcp-server)](https://www.npmjs.com/package/@gblin-protocol/mcp-server)

GBLIN is a non-custodial index of cbBTC, WETH and USDC on Base. Shares are minted at net asset value against a deposit and redeemed pro rata in kind, with no fee and no price feed on the way out. The vault never swaps: it rebalances through a Dutch auction that anyone can fill, and it accepts payments by signature (EIP-3009) like USDC does. A crash shield cuts the weight of a risk asset during severe, oracle-measured drawdowns. Every parameter is bounded in code and governed by a 48-hour timelock.

This document is the specification. What is true is here and on-chain; when the two disagree, the chain wins.

## Contents

1. [Deployment](#1-deployment)
2. [Architecture](#2-architecture)
3. [Shares and NAV](#3-shares-and-nav)
4. [Fees](#4-fees)
5. [Minting](#5-minting)
6. [Redemption](#6-redemption)
7. [Rebalancing by auction](#7-rebalancing-by-auction)
8. [Crash shield](#8-crash-shield)
9. [Payments by signature](#9-payments-by-signature)
10. [Governance](#10-governance)
11. [Sequencer sentinel](#11-sequencer-sentinel)
12. [Invariants](#12-invariants)
13. [Security](#13-security)
14. [Building and verifying](#14-building-and-verifying)

## 1. Deployment

| Contract | Address |
|---|---|
| `GBLIN` (vault, ERC-20 share) | [`0xc2181d975c05c8c724b334bcED0764c0b86B1D53`](https://basescan.org/address/0xc2181d975c05c8c724b334bcED0764c0b86B1D53) |
| `GBLINLens` | [`0xfCFea8027019E8551A1f09AD91532471F5D26f61`](https://basescan.org/address/0xfCFea8027019E8551A1f09AD91532471F5D26f61) |
| `GBLINZap` | [`0x0E9D6Ceb6D313b021622C121Cda9C62e86e60200`](https://basescan.org/address/0x0E9D6Ceb6D313b021622C121Cda9C62e86e60200) |
| `SequencerSentinel` | [`0x9F13C5c46a864183e1c57Ec02837fe5B980D3F67`](https://basescan.org/address/0x9F13C5c46a864183e1c57Ec02837fe5B980D3F67) |
| `UniswapV3Adapter` | [`0x062654Bf9b5Bd88b84D7861a8f22ba94dECd9d3F`](https://basescan.org/address/0x062654Bf9b5Bd88b84D7861a8f22ba94dECd9d3F) |
| `CowFillAgent` (the vault's fill agent) | [`0x0f4307A5Eb7D33d04Cb68fb0bA4d47a56C7E2fc8`](https://basescan.org/address/0x0f4307A5Eb7D33d04Cb68fb0bA4d47a56C7E2fc8) |
| `GblinAuctionOrder` (auction order generator) | [`0x156Ffd19819e02d9809cED8fa1416EDCD31ddaB9`](https://basescan.org/address/0x156Ffd19819e02d9809cED8fa1416EDCD31ddaB9) |
| Timelock (owner-elect) | [`0x6aBeC8716fFeEcf7C3D6e68255b4797113E8e5Dd`](https://basescan.org/address/0x6aBeC8716fFeEcf7C3D6e68255b4797113E8e5Dd) |

Network: Base mainnet (chain id 8453). Compiler: Solidity 0.8.37, `via_ir`, optimizer runs 1, EVM `cancun`, no CBOR metadata. Sources verified on Sourcify (full match) and Basescan. Creation transactions, launch parameters and previous deployments: [`docs/deployments.md`](docs/deployments.md).

Token: name `Global Balanced Liquidity Index`, symbol `GBLIN`, 18 decimals. Basket at launch: cbBTC 45%, WETH 45%, USDC 10%.

## 2. Architecture

The vault holds the assets and the shares. Everything that needs a price, a swap or a bid is either read through the Lens or executed through a peripheral contract that calls the vault.

| Component | Role |
|---|---|
| `GBLIN` | ERC-20 share and custody. Mints at NAV, redeems in kind, runs the auction and the shield, accrues fees, accepts EIP-3009 payments. Non-upgradeable; no proxy. |
| `GBLINLens` | Read-only views: quotes, configuration, basket rows, auction state, pending withdrawals, cooldowns. Takes the vault as its first argument. |
| `GBLINZap` | Mints with any token and exits to ETH. It swaps on an adapter and mints or redeems on the vault in the same call. The vault itself never touches a pool. |
| `SequencerSentinel` | Passes the L2 sequencer uptime feed through and lets a guardian report the sequencer down. While down, the vault refuses mints and auction fills; redemptions are not affected. |
| `UniswapV3Adapter`, `AerodromeAdapter` | Swap adapters used by the Zap, with a TWAP band that refuses a pool price too far from the oracle. |
| `CowFillAgent` | The vault's fill agent: lets CoW Protocol solvers fill the auction inside a settlement, at the auction price or better. Its signature check is delegated to CoW Protocol's `ComposableCoW`. |
| `GblinAuctionOrder` | Conditional order of CoW Protocol's programmatic order framework: for one basket row it cuts, from the vault's live state, the order a solver can settle against the auction, and at settlement it accepts that order only against the fill opened in the same block. |

Sources: [`src/`](src/). Interfaces with full NatSpec: [`src/interfaces/`](src/interfaces/). Libraries: [`src/libraries/OracleLib.sol`](src/libraries/OracleLib.sol), [`src/libraries/ShieldLib.sol`](src/libraries/ShieldLib.sol), [`src/libraries/GPv2OrderLib.sol`](src/libraries/GPv2OrderLib.sol).

## 3. Shares and NAV

The value of the vault is the sum of every basket row priced by its Chainlink feed, in ETH. The NAV of a share is that value divided by the supply. `navPerShare(0)` and `totalEthValue(0)` expose it; `isNavReliable()` says whether the vault can price itself right now.

A row is priced only while its feed answers with a positive value within its allowed age — the pricing age, 2 hours at launch, or 26 hours for the feed of a stable asset, which updates less often — and its token answers `balanceOf`. A row that cannot be priced counts as zero in the NAV and loses its weight until the price returns; mints and quotes are refused while any row is in that state, so a deposit cannot be priced against a hole. Mints and bids move value at a price and require fresher feeds: 30 minutes at launch for the feeds of non-stable assets.

The first mint sets the scale: the value already in the vault divided by one million virtual shares. A small seed of shares is held by an address without a key, so the supply never returns to zero and the scale is anchored for the life of the vault.

## 4. Fees

| Fee | Rate at launch | Paid how |
|---|---|---|
| Protocol fee on mints with ETH or WETH | 0.05% of the deposit | Minted as shares to the fee recipient |
| Stability fee on mints with ETH or WETH | 0.05% of the deposit | Stays in the vault: value no share was issued against, so it lifts the NAV of every share |
| In-kind deposit fee | Floor 0.50%; a deposit that moves its row away from its target pays a deviation tax on top, up to 1.50% | The protocol part (0.05%) is minted as shares to the fee recipient; the rest stays in the vault |
| Management fee | 0.50% per year of the supply | Accrued pro rata to the time elapsed and minted as shares to the fee recipient on every mint, redemption, bid and `refreshWeights` |
| Redemption in kind | none | — |
| Transfers, including by signature | none | — |

Bounds: the two mint fees sum to at most 1%, and the protocol fee never exceeds the in-kind floor; the in-kind floor is at most 3% and the tax at most 5%; the management fee is at most 2% per year. All are set through the timelock (section 10).

## 5. Minting

Every mint prices the deposit with the oracles, takes the fee, and issues shares at NAV. There is no minimum deposit.

- `buyGBLIN(minOut)` with ETH: the ETH is wrapped and kept as WETH.
- `buyGBLINWithWeth(amount, minOut, receiver)`: pulls WETH; the receiver may differ from the caller.
- `buyGBLINInKind(token, amountIn, minOut)`: deposits a basket asset directly and pays the in-kind fee.
- Any other token: `GBLINZap.buyGBLINWithToken(tokenIn, amountIn, minWethOut, minOut, venueData, receiver)` swaps to WETH on an adapter and mints in the same transaction. Both minimums are enforced; the Zap never keeps shares and never receives them for itself.

A mint records a redemption cooldown (20 seconds at launch) for the minter only when the minter is also the receiver, so that a deposit on someone's behalf cannot keep their exit closed.

## 6. Redemption

`sellGBLIN(gblinAmount)` burns the shares and transfers the pro-rata slice of every basket row to the holder; the WETH slice is unwrapped and paid as ETH, and a holder that cannot receive ETH is credited in WETH instead. It reads no price feed, charges no fee and cannot be paused: it is the exit that is always open. The vault relies on each basket token to deliver the full amount it is asked to transfer, and a token is listed only if it does.

A leg that cannot be transferred at the moment of redemption — a token that reverts, or a transfer that runs out of the gas cap — is credited to the holder and collected later with `claimPending(token)`. A token that does not answer `balanceOf` is not delivered and creates no credit.

To leave in ETH: `GBLINZap.sellGBLINForEth(shares, minEthOut, venueData, receiver)` redeems in kind on the vault and sells every leg on the adapters. It is all or nothing: a leg the adapter cannot sell, or that the vault credits instead of delivering, reverts the whole call and the holder keeps the shares. The ETH paid must reach `minEthOut` and, while the vault can price itself, the NAV value of the shares less the Zap's slippage bound; units of a leg the adapter leaves unsold are forwarded to the receiver.

## 7. Rebalancing by auction

The vault does not rebalance itself and pays nobody to do it. When the largest deviation of a row from its target weight exceeds the opening band (7% of the vault's value at launch) the vault opens a Dutch auction; it closes when every deviation is at or below the closing band (1.75%).

`bid(index, vaultBuysAsset, amountIn, minOut, data)` trades with the vault at the oracle price adjusted by the current premium:

- the premium starts at a discount (100 bps at launch: the vault asks less than the oracle price), rises linearly to the cap (25 bps) over one ramp (3,600 seconds), holds there for a second ramp, then starts again — `auctionPremiumBps()` exposes it;
- the bidder brings the input token: the asset when the vault buys it (the row is below target), WETH when the vault sells it;
- the input is reduced to what closes the gap, so a bid never pushes a row past its target, and to the WETH the vault actually holds; a bid that would change nothing reverts;
- no bid is accepted in the block that opened the auction;
- `data` is passed to an optional callback (`IAuctionCallback.onAuctionFill`) so a filler can source the input after the vault has paid the output.

Delisted rows carry no weight and are sold through the same auction. The auction state per row — open, premium, side, gap — is served by `GBLINLens.auction(vault, i)`.

**Fills by CoW Protocol solvers.** The vault's fill agent (`setAddress(6, …)`) may bid without paying at once: the vault sends it the output, calls it back, and leaves the fill open for the rest of the block instead of pulling the input. For the cbBTC and USDC rows the agent has registered with `ComposableCoW` a conditional order whose handler, `GblinAuctionOrder`, cuts the discrete order from the vault's state — side, size and price as `bid` would compute them — stable for a five-minute bucket, and CoW Protocol's watch-tower posts it to the order book. A solver settles it in one transaction: a pre-hook opens the fill (`openFill`), the settlement verifies the order through the agent's EIP-1271 signature, which checks it against the open fill at the auction price or better, and a post-hook (`refreshWeights`) closes the fill and returns every unit of both tokens, surplus included, to the vault. While a fill is open and a swap is half done, every function of the vault that moves value reverts. Whether solvers fill an auction of the vault's current size is a matter of their economics, not of the contract.

## 8. Crash shield

For every row the shield keeps two decaying price peaks — a fast one (0.5% per day at launch) and a slow one (0.15% per day). When the drawdown from the higher of the two exceeds a volatility-adjusted threshold (base 15%, bounded between 15% and 50%), the row's weight is cut in proportion to how far the drawdown has moved from the threshold toward the full-slash drawdown (30%), down to the share kept at full severity (20%). The weight removed goes, in equal parts, to stable rows that are at their peg and not shielded themselves; without such rows it stays in WETH. The shield deactivates only when the drawdown falls back within the recovery band (8%).

The shield refreshes on every mint, redemption, bid and on `refreshWeights()`, which anyone can call. Its full parameter set is exposed by `GBLINLens.configShield(vault)` and the arithmetic lives in [`ShieldLib`](src/libraries/ShieldLib.sol).

## 9. Payments by signature

The share implements EIP-3009: `transferWithAuthorization`, `receiveWithAuthorization` and `cancelAuthorization`, with signatures either as `(v, r, s)` or as bytes, which also admits ERC-1271 contract signatures. The EIP-712 domain is `Global Balanced Liquidity Index`, version `1`, exposed by `eip712Domain()` (EIP-5267). An authorization is single-use and time-bounded; a replay reverts.

This lets an agent pay in GBLIN over a facilitator the way it pays in USDC, without holding ETH for gas. Transfers by signature carry no fee.

## 10. Governance

The owner of the vault is the 48-hour timelock at `0x6aBeC8716fFeEcf7C3D6e68255b4797113E8e5Dd` (minimum delay 172,800 seconds, grace period 14 days, open executor, proposer and canceller roles held by separate addresses). Ownership moved in two steps: `transferOwnership` by the deployer, then `acceptOwnership` by the timelock, which for a timelock is itself a scheduled operation; it executed on 2026-09-22. From that point every owner action passes through the 48-hour delay. `get_governance_state` in the MCP server and `owner()` and `pendingOwner()` on the vault report the state.

Every parameter is set through `setParam(key, values)` with hard bounds enforced in code:

| Key | Group | Bounds |
|---|---|---|
| 2 | Shield: base threshold, volatility multiplier, recovery band, slash multiplier | threshold below the full slash; multiplier ≤ 100000; band below the minimum crash; slash ≤ 10000 |
| 3 | Mint fees: protocol, stability | sum ≤ 100 bps; protocol ≤ in-kind floor |
| 4 | Auction: start discount, cap, ramp | 1–300 bps; ≤ 300 bps; 1 minute to 30 days |
| 5 | Minimum deposit | ≤ 10 ETH |
| 6 | Feed ages: pricing, trading | 10 minutes to 6 hours; 1 minute to the pricing age |
| 7 | Peg band of stable assets | ≤ 1000 bps |
| 8 | Auction band: opening, closing | 1–10000 bps; closing below opening |
| 9 | Shield curve: slow peak decay, full-slash drawdown | ≤ 10000; above the minimum crash and the base threshold |
| 11 | Shield tuning: minimum crash, maximum crash, fast peak decay, volatility update interval | minimum above the recovery band and below the full-slash drawdown, at most the maximum; maximum and decay ≤ 10000; interval 1 second to 30 days |
| 13 | In-kind fee: floor, deviation tax | protocol fee to 300 bps; ≤ 500 bps |
| 14 | Redemption cooldown | ≤ 1 hour |
| 16 | Basket size cap | current length to 50 |
| 17 | Listing delay | ≤ 30 days |
| 19 | Management fee per year | ≤ 200 bps; accrued at the previous rate first |

`setAddress(key, address)` sets the sequencer feed (2), the fee recipient (3), the ETH price feed (5) and the fill agent (6); a new ETH feed must have the same decimals and declared identity as the current one and answer with a live price, and a new fee recipient receives the management fee accrued so far before it changes. `setBaseWeights` sets the target weights. Assets enter through `proposeAsset`, with a base weight of at most 30%, and, after the listing delay, `executeAssetAddition`, which pulls a probe of the asset so the vault is never empty and rejects tokens that do not deliver the exact amount. `assetAction` delists, relists or abandons a row: a delisted row keeps its balance in NAV and is sold through the auction; an abandoned row is quarantined forever; abandoning requires a delisted row whose feed has given no price for seven days, and the NAV must stay positive afterwards.

What governance cannot do: move holders' assets, mint shares to itself, exceed a bound above, pause redemptions, upgrade the code, or act without the timelock's delay once the handover has executed. Details: [`docs/governance.md`](docs/governance.md).

## 11. Sequencer sentinel

The vault reads the L2 sequencer uptime through `SequencerSentinel`, which passes the Chainlink feed through unchanged and lets a guardian report the sequencer as down at once. While it reports down, mints and auction fills are refused; redemptions, in kind or through the Zap, and credit claims are not affected. A pause always expires: the guardian's pauses are budgeted (one stretch of at most 30 days, then a rest), and the owner's are capped at the same length per call.

## 12. Invariants

These hold by construction and are exercised by the test campaigns described in [`audits/README.md`](audits/README.md):

- Redemption in kind is always open: it reads no feed, charges no fee, and is not gated by the sentinel.
- Every share is backed by the basket; the vault holds nothing that is not counted in the NAV and counts nothing it does not hold.
- No mint or trade is priced while a row cannot be priced.
- A bid never moves a row past its target and never uses WETH the vault does not hold.
- Fees are minted, never taken out of the reserves; the management fee is accrued at the old rate before the rate changes.
- The supply never returns to zero.
- Every governance change stays within its bound and, once the handover has executed, waits 48 hours.

## 13. Security

This release has had no paid third-party audit. It was reviewed line by line by the maintainer and by three AI systems — Fable 5.1, Grok 4 (Expert) and ChatGPT (Thinking) — with reproducible reading tests; the campaigns of unit, fuzz, invariant, fork, mutation and symbolic testing are summarized in [`audits/README.md`](audits/README.md), together with what was not done. Paid audits will follow as the protocol earns its own budget.

Reports of vulnerabilities: [`SECURITY.md`](SECURITY.md). Findings reported so far and their status: [`KNOWN_ISSUES.md`](KNOWN_ISSUES.md).

## 14. Building and verifying

The repository contains the exact sources and library files the verified bytecode was compiled from, and the compiler settings in [`foundry.toml`](foundry.toml).

```bash
forge build
```

The runtime bytecode of `GBLIN` produced by this build is identical to the code at `0xc2181d975c05c8c724b334bcED0764c0b86B1D53` except for the immutable values written at deployment. To check it yourself:

```bash
cast code 0xc2181d975c05c8c724b334bcED0764c0b86B1D53 --rpc-url https://mainnet.base.org
jq -r .deployedBytecode.object out/GBLIN.sol/GBLIN.json
```

## Links

- Website and application: [gblin.digital](https://gblin.digital)
- Agent documentation and MCP server: [gblin.digital/agents](https://gblin.digital/agents) · [`@gblin-protocol/mcp-server`](https://www.npmjs.com/package/@gblin-protocol/mcp-server)
- Previous deployments: [`legacy/`](legacy/) and [`docs/deployments.md`](docs/deployments.md)

MIT © GBLIN Protocol
