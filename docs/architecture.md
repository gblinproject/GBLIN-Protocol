# GBLIN Protocol — Architecture

This document expands on the high-level architecture summarized in the [main README](../README.md#1-protocol-architecture).

## Components

### 1. Core Contract ([GBLIN_V5.sol](cci:7://file:///c:/Users/Roby-Caro/Documents/GitHub/GBLIN_WEBAPP/contracts/GBLIN_V5.sol:0:0-0:0))

Single ERC-20 contract that:
- Mints/burns GBLIN tokens.
- Custodies basket assets (cbBTC, WETH, USDC).
- Computes NAV from Chainlink oracles.
- Executes Uniswap V3 swaps for rebalancing.
- Manages stability fund and yield distribution.

### 2. External Dependencies

| Dependency | Purpose |
|---|---|
| OpenZeppelin Contracts | ERC20, ERC20Permit, ReentrancyGuard |
| Chainlink AggregatorV3Interface | Price feeds + sequencer feed |
| Uniswap V3 SwapRouter | Asset swaps on Base |
| WETH9 | ETH wrapping |

### 3. Off-chain Components

| Component | Role |
|---|---|
| Keepers (any address) | Trigger `incentivizedRebalance()` and earn 0.0001 ETH |
| Frontend (gblin.digital) | UX layer for buy/sell/redeem |
| Dune Analytics | Public dashboard |

## Data Flow

### Buy flow

```
User → buyGBLIN(minOut) [+ETH]
  → IWETH.deposit()
  → _quoteBuy: nav, founderFee, stabilityFee
  → _mint(user, gblinOut)
  → withdraw founderFee → founderWallet
  → for each non-WETH asset: swap WETH→asset on Uniswap V3
  → emit Minted
  → _autoDistributeYield
```

### Sell flow

```
User → sellGBLIN(amount)
  → cooldown check
  → _getPreBurnShares: pro-rata WETH + each asset
  → _burn(user, amount)
  → withdraw WETH → user
  → for each asset: transfer asset → user
  → emit Burned
```

### Rebalance flow

```
Keeper → incentivizedRebalance(idx, isWethToAsset, amount)
  → minSwapRequired check
  → refreshWeights
  → compute target/current ETH value
  → swap on Uniswap V3 with 2% maxSlippage
  → reward 0.0001 ETH from stabilityFund → keeper
```

## Storage Layout

The basket is stored as a dynamic array (`Asset[] basket`) for gas efficiency at the cost of slightly higher iteration cost. Trade-off accepted because:
- Number of basket assets remains small (≤ 5 expected).
- Iteration occurs only during NAV reads and rebalances.

## Upgradeability

**The contract is non-upgradeable.** A migration to a new version requires deploying a new contract and providing migration tooling for users (in-kind redeem then re-mint on new contract). This is a deliberate trust-minimization choice.
