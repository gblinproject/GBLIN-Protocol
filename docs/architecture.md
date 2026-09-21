# Architecture

This document expands on the overview in the [README](../README.md#2-architecture).

## Components

| Contract | Source | Responsibility |
|---|---|---|
| `GBLIN` | [`src/GBLIN.sol`](../src/GBLIN.sol) | ERC-20 share (Solady base, EIP-3009), custody of the basket, NAV, mints at NAV, redemption in kind with credits, Dutch auction, crash shield, fee accrual, ownership in two steps |
| `GBLINLens` | [`src/periphery/GBLINLens.sol`](../src/periphery/GBLINLens.sol) | Read-only views over the vault's storage: quotes, configuration, rows, auction, credits, cooldowns |
| `GBLINZap` | [`src/periphery/GBLINZap.sol`](../src/periphery/GBLINZap.sol) | Mint with any token; exit to ETH all or nothing. Swaps through an adapter, then calls the vault in the same transaction |
| `SequencerSentinel` | [`src/SequencerSentinel.sol`](../src/SequencerSentinel.sol) | Pass-through of the sequencer uptime feed with a bounded guardian pause |
| `UniswapV3Adapter`, `AerodromeAdapter` | [`src/adapters/`](../src/adapters/) | Swap adapters with a TWAP band against the oracle |
| `CowFillAgent` | [`src/fillers/CowFillAgent.sol`](../src/fillers/CowFillAgent.sol) | The vault's fill agent (`setAddress(6, …)`): bids without paying at once, lets CoW Protocol's relayer spend the output, returns everything to the vault on close. Owns the conditional orders on `ComposableCoW`; its EIP-1271 check is delegated there |
| `GblinAuctionOrder` | [`src/fillers/GblinAuctionOrder.sol`](../src/fillers/GblinAuctionOrder.sol) | Handler of the conditional orders: `getTradeableOrder` cuts the discrete order from the vault's state; `verify` accepts it only against the fill open in the same block |
| `OracleLib`, `ShieldLib`, `GPv2OrderLib` | [`src/libraries/`](../src/libraries/) | Feed reading with freshness and identity checks; shield and in-kind fee arithmetic; the CoW Protocol order struct and its EIP-712 hash |

External dependencies: OpenZeppelin (`SafeERC20`, `ReentrancyGuard`, `Math`, `SafeCast`, interfaces), Solady (`ERC20`, `SafeTransferLib`, `SignatureCheckerLib`), Chainlink aggregators and the Base sequencer uptime feed, WETH9, Uniswap V3 and Aerodrome for the adapters, and CoW Protocol's settlement contract and `ComposableCoW` for the fill agent. The exact library files are vendored under [`lib/`](../lib/).

## Flows

### Mint with ETH

```
holder → GBLIN.buyGBLIN(minOut) [+ETH]
  → sequencer up? feeds fresh for trading?
  → shield refresh, management fee accrual
  → value the deposit at the ETH feed; take protocol fee (shares to the fee recipient) and stability fee (stays)
  → mint shares at NAV to the holder; record the cooldown for the minter
  → emit Minted
```

### Mint with another token

```
holder → GBLINZap.buyGBLINWithToken(tokenIn, amountIn, minWethOut, minOut, venueData, receiver)
  → pull tokenIn; swap to WETH on the adapter (TWAP band, minWethOut)
  → GBLIN.buyGBLINWithWeth(weth, minOut, receiver)
```

### Redemption in kind

```
holder → GBLIN.sellGBLIN(shares)
  → cooldown check (only for the holder's own mints)
  → management fee accrual; close an open fill if any
  → burn; for each row transfer the pro-rata slice with a gas cap
  → a leg that fails is credited (claimPending); a token that does not answer balanceOf is skipped
  → emit Redeemed
```

### Exit to ETH

```
holder → GBLINZap.sellGBLINForEth(shares, minEthOut, venueData[], receiver)
  → pull shares; GBLIN.sellGBLIN on the Zap's behalf
  → sell every non-WETH leg on the adapters; unwrap; deliver ETH ≥ minEthOut
  → any failure reverts the whole call: the holder keeps the shares
```

### Auction

```
anyone → GBLIN.bid(index, vaultBuysAsset, amountIn, minOut, data)
  → sequencer up, feeds fresh, shield refresh, fee accrual, drift check
  → premium = auctionPremiumBps(); price = oracle × (1 + premium)
  → input trimmed to the gap and to the WETH held; output computed at that price
  → pay the output; call the optional callback with data; pull the input; require minOut
  → emit AuctionFill; close the auction if every row is within the closing band
```

### Auction filled by CoW Protocol solvers

```
watch-tower → ComposableCoW.getTradeableOrderWithSignature(agent, params, "", [])
  → GblinAuctionOrder.getTradeableOrder: fill agent set? no fill open? auction open, gap > 0, not the opening block?
  → side, size and price as bid computes them, with the premium at the start of a five-minute bucket
  → a condition that can change reverts with a polling error (PollTryNextBlock, PollTryAtEpoch), so the order is polled again;
    only an order that can never be valid (another owner, a WETH or abandoned row) reverts with OrderNotValid
  → the watch-tower posts the order with its appData hash to the CoW Protocol order book

solver → GPv2Settlement.settle(...)
  pre-hook   → CowFillAgent.openFill(row, side) → GBLIN.bid(..., data = 0x01)
               → the vault pays the output to the agent, calls onAuctionFill, leaves the fill open
               → the agent records the fill and approves the relayer for the output only
  signature  → CowFillAgent.isValidSignature → ComposableCoW.isValidSafeSignature → GblinAuctionOrder.verify
               → same block, same tokens, no fee, receiver = agent, ERC-20 balances, price ≥ the fill's, registered appData
  trade      → the relayer pulls the output; the solver delivers the input to the agent
  post-hook  → GBLIN.refreshWeights → close the fill: the agent returns both tokens, surplus included
```

While the fill is open and the swap is half done, every function of the vault that moves value reverts. A fill left open in an earlier block is closed by any call of the vault, or by anyone through `CowFillAgent.emergencyClose`.

### Payment by signature

```
payer signs TransferWithAuthorization(from, to, value, validAfter, validBefore, nonce)
relayer → GBLIN.transferWithAuthorization(..., signature)
  → domain "Global Balanced Liquidity Index" / "1"; nonce unused; window open
  → transfer; emit AuthorizationUsed
```

## Storage and immutables

The basket is a dynamic array of rows, each packed into a fixed number of slots read by the Lens. Addresses that never change — WETH, the adapters' venues — are immutables, so the deployed bytecode differs from a fresh build only in those values. There is no proxy and no upgrade path: a successor is a new deployment, and holders move by redeeming in kind and minting again.
