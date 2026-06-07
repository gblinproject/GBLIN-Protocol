# GBLIN V5 — Technical Specification

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Network: Base](https://img.shields.io/badge/Network-Base%20Mainnet-blue.svg)](https://basescan.org/address/0x38DcDB3A381677239BBc652aed9811F2f8496345)
[![Solidity](https://img.shields.io/badge/Solidity-%5E0.8.20-363636.svg)](https://soliditylang.org/)
[![Version](https://img.shields.io/badge/Version-V5-green.svg)](https://github.com/gblinproject/Whitepaper)
[![Governance: 48h Timelock](https://img.shields.io/badge/Governance-48h%20Timelock-1f6feb.svg)](https://basescan.org/address/0x6aBeC8716fFeEcf7C3D6e68255b4797113E8e5Dd)
[![MCP Registry](https://img.shields.io/badge/MCP%20Registry-Live-9b59b6.svg)](https://registry.modelcontextprotocol.io/v0/servers?search=gblin)
[![npm](https://img.shields.io/npm/v/@gblin-protocol/mcp-server.svg?label=@gblin-protocol/mcp-server)](https://www.npmjs.com/package/@gblin-protocol/mcp-server)
[![Audit](https://img.shields.io/badge/Audit-Public-orange.svg)](#audit-status)

> **Global Balanced Liquidity Index** — A fully collateralized, autonomously rebalanced, on-chain index of digital assets, deployed on Base Mainnet. Owned by a 48-hour Timelock Controller. Native AI-agent treasury via the Model Context Protocol.

---

## Abstract

GBLIN is a non-custodial ERC-20 index token whose price is deterministically derived from a basket of underlying assets (cbBTC, WETH, USDC) held by the contract itself. Unlike algorithmic stablecoins or AMM-priced tokens, GBLIN's value is computed on-chain from oracle-verified Net Asset Value (NAV) at every interaction. The protocol introduces four innovations over traditional on-chain index funds:

1. **Crash Shield** — an automatic, oracle-driven mechanism that reduces exposure to any basket asset undergoing a drawdown greater than 20% from its recent peak, redistributing weight to healthy stable assets.
2. **Permissionless rebalancing** — any address can trigger a rebalance and earn a fixed reward (0.0001 ETH) from the protocol's stability fund, eliminating reliance on a centralized keeper.
3. **In-Kind facility** — institutional-grade mint/redeem flows that bypass swap slippage by depositing/receiving the basket assets directly, mirroring the authorized-participant mechanism of traditional ETFs.
4. **AI-agent native** — a first-class Model Context Protocol (MCP) server (`@gblin-protocol/mcp-server`) lets autonomous agents on Base hold treasury in GBLIN and Just-In-Time swap to USDC for x402 micropayments. Listed on the official Anthropic MCP Registry as `io.github.gblinproject/gblin-mcp-server` and natively compatible with Coinbase AgentKit's MCP extension.

The contract is owned by a **48-hour OpenZeppelin Timelock Controller** with an immutable `MIN_DELAY`: every administrative action (parameter change, oracle update, ownership transfer) is enforced on-chain to wait 172,800 seconds before execution. This makes GBLIN one of the few index protocols on Base where admin power is verifiably delay-locked, eliminating the classic rug-then-attack vector.

This document specifies the contract's mathematical model, function-level behavior, security assumptions, governance architecture, and historical case studies demonstrating capital protection during real market events.

---

## Deployment

| Field | Value |
|---|---|
| **Contract address** | [`0x38DcDB3A381677239BBc652aed9811F2f8496345`](https://basescan.org/address/0x38DcDB3A381677239BBc652aed9811F2f8496345) |
| **Owner (Timelock Controller)** | [`0x6aBeC8716fFeEcf7C3D6e68255b4797113E8e5Dd`](https://basescan.org/address/0x6aBeC8716fFeEcf7C3D6e68255b4797113E8e5Dd) |
| **Network** | Base Mainnet (chain ID 8453) |
| **Version** | V5 |
| **Compiler** | Solidity ^0.8.20 |
| **Optimizer** | Enabled (200 runs) |
| **License** | MIT |
| **DEX integration** | Uniswap V3 (Base) |
| **Oracles** | Chainlink price feeds + Base sequencer feed |
| **MCP Server** | [`@gblin-protocol/mcp-server`](https://www.npmjs.com/package/@gblin-protocol/mcp-server) — `io.github.gblinproject/gblin-mcp-server` |
| **ElizaOS Plugin** | [`plugin-gblin`](https://www.npmjs.com/package/plugin-gblin) — community plugin for Eliza agents |

### Useful links

- Website: [gblin.digital](https://gblin.digital)
- Whitepaper: [GBLIN_WHITE_PAPER_V5.pdf](https://github.com/gblinproject/Whitepaper/raw/main/GBLIN_WHITE_PAPER_V5.pdf)
- Dune Analytics: [dune.com/gblin/dashboard](https://dune.com/gblin/dashboard)
- Aerodrome V5 pool: [`0x7dcd...ae1b`](https://aerodrome.finance/)
- **MCP Server (npm)**: [`@gblin-protocol/mcp-server`](https://www.npmjs.com/package/@gblin-protocol/mcp-server)
- **MCP Registry listing**: [`io.github.gblinproject/gblin-mcp-server`](https://registry.modelcontextprotocol.io/v0/servers?search=gblin)
- **MCP repo (AI-agent toolkit)**: [github.com/gblinproject/GBLIN-MCP](https://github.com/gblinproject/GBLIN-MCP)
- **ElizaOS plugin (npm)**: [`plugin-gblin`](https://www.npmjs.com/package/plugin-gblin)
- **ElizaOS plugin repo**: [github.com/gblinproject/GBLIN_PLUGIN](https://github.com/gblinproject/GBLIN_PLUGIN)
- **Timelock Controller (owner)**: [`0x6aBeC8716fFeEcf7C3D6e68255b4797113E8e5Dd`](https://basescan.org/address/0x6aBeC8716fFeEcf7C3D6e68255b4797113E8e5Dd)
- X / Twitter: [@GBLIN_Protocol](https://x.com/GBLIN_Protocol)
- Farcaster: [@gblin](https://warpcast.com/gblin)
- Email: info@gblin.digital

---

## Table of Contents

1. [Protocol Architecture](#1-protocol-architecture)
2. [Token Architecture](#2-token-architecture)
3. [The Basket: Composition and Weights](#3-the-basket-composition-and-weights)
4. [NAV (Net Asset Value) Calculation](#4-nav-net-asset-value-calculation)
5. [Fee System and Redistribution](#5-fee-system-and-redistribution)
6. [Autonomous Rebalance Mechanism](#6-autonomous-rebalance-mechanism)
7. [The Crash Shield: Mathematics of Protection](#7-the-crash-shield-mathematics-of-protection)
8. [Historical Case Studies](#8-historical-case-studies)
9. [In-Kind Facility (ETF-style Mint/Redeem)](#9-in-kind-facility-etf-style-mintredeem)
10. [AI Agent Integration (Model Context Protocol)](#10-ai-agent-integration-model-context-protocol)
11. [Complete Function Reference](#11-complete-function-reference)
12. [Security and Defenses](#12-security-and-defenses)
13. [Audit Status](#13-audit-status)
14. [Bug Bounty & Responsible Disclosure](#14-bug-bounty--responsible-disclosure)
15. [Repository Structure](#15-repository-structure)
16. [Contributing](#16-contributing)
17. [References & Further Reading](#17-references--further-reading)
18. [Technical Glossary](#18-technical-glossary)

---

## 1. Protocol Architecture

```mermaid
flowchart TB
    User([User / Wallet]) -->|ETH or ERC-20| Buy[buyGBLIN / mintInKind]
    User -->|GBLIN| Sell[sellGBLIN / redeemInKind]
    Keeper([Keeper / Bot]) -->|trigger| Rebal[incentivizedRebalance]
    Agent([AI Agent via MCP]) -->|read NAV / calldata| Core
    TL([48h Timelock Controller]) -->|admin actions, delay-locked| Core

    Buy --> Core{GBLIN Contract}
    Sell --> Core
    Rebal --> Core

    Core -->|swap| Uni[Uniswap V3 Router]
    Core -->|read price| Chainlink[Chainlink Oracles]
    Core -->|check L2 health| Seq[Base Sequencer Feed]

    Core -.holds.-> cbBTC
    Core -.holds.-> WETH
    Core -.holds.-> USDC

    Core -->|reward 0.0001 ETH| Keeper
    Core -->|fee 0.05%| Founder([Founder Wallet])
    Core -->|fee 0.05%| Stab[(Stability Fund)]
    Stab -.surplus → NAV.-> Holders([GBLIN Holders])
```

The contract is the only custodian of basket assets. Every read (NAV, quotes) and every write (mint, burn, rebalance) is fully self-contained. There are no external admin keys able to move user funds: the sole admin role is the **48h Timelock Controller**, which can only execute parameter changes after a 172,800-second delay. Ownership can also be permanently renounced.

---

## 2. Token Architecture

GBLIN inherits from OpenZeppelin's `ERC20`, `ERC20Permit`, and `ReentrancyGuard`.

```solidity
contract GBLIN_GlobalBalancedLiquidityIndex is ERC20, ERC20Permit, ReentrancyGuard
```

### Main characteristics

| Property | Value |
|---|---|
| Name | Global Balanced Liquidity Index |
| Symbol | GBLIN |
| Decimals | 18 |
| Initial supply | 0 (uncapped, mintable on deposit) |
| ERC20Permit | Yes (EIP-2612 signatures supported) |
| Reentrancy Guard | Yes on all stateful external functions |

### Core state variables

```solidity
Asset[] public basket;             // Asset basket
uint256 public stabilityFund;      // Stability reserve in WETH
uint256 public maxInternalSlippage = 200;   // 2% maximum slippage
uint256 public reserveFloor = 0.05 ether;
uint256 public reserveCeiling = 2 ether;
```

### Immutable constants

```solidity
FOUNDER_FEE_BPS    = 5      // 0.05% to creator
STABILITY_FEE_BPS  = 5      // 0.05% to stability fund
BPS_DENOMINATOR    = 10000
MIN_DEPOSIT        = 0.0005 ether
ORACLE_TIMEOUT     = 86400  // 24 hours
TIMELOCK_DURATION  = 48 hours
CRASH_THRESHOLD_BPS = 2000  // 20% drawdown triggers crash shield
SLASH_MULTIPLIER   = 2000   // reduction to 20% of base weight
PEAK_DECAY_PER_DAY = 50     // 0.5% decay per day
YIELD_INTERVAL     = 7 days
```

---

## 3. The Basket: Composition and Weights

At deployment, the basket is initialized as follows:

| Index | Asset | Base Weight | Pool Fee | Stable | Chainlink Oracle |
|---|---|---|---|---|---|
| 0 | **cbBTC** | 45.00% | 0.05% | No | `0x07DA0E54...59f9D` |
| 1 | **WETH** | 45.00% | — | No | `0x71041ddd...6Bb70` |
| 2 | **USDC** | 10.00% | 0.05% | Yes | `0x7e860098...2bc6B` |

### `Asset` struct

```solidity
struct Asset {
    address token;          // Token address
    address oracle;         // Chainlink price feed
    uint24  poolFee;        // Uniswap V3 fee tier
    bool    isStable;       // Is it a stablecoin?
    uint256 baseWeight;     // Permanent target weight (BPS)
    uint256 dynamicWeight;  // Effective current weight (BPS)
    uint256 peakPrice;      // Recent maximum price (for crash shield)
    uint256 lastPeakUpdate; // Last peak update timestamp
}
```

**Crucial distinction:**
- `baseWeight` = desired weight under normal conditions
- `dynamicWeight` = effective weight after Crash Shield and redistribution

---

## 4. NAV (Net Asset Value) Calculation

The NAV is the mathematical core of GBLIN. It answers: *"How much is one GBLIN worth in ETH?"*

### Formula

$$
\text{NAV} = \frac{\sum_{i=1}^{n} \text{balance}_i \cdot \text{price}_i^{\text{ETH}} - \text{stabilityFund}}{\text{totalSupply} - \text{contractBalance}}
$$

Where:
- $\text{balance}_i$ = on-chain balance of asset $i$
- $\text{price}_i^{\text{ETH}}$ = Chainlink-derived price of asset $i$ in ETH
- $\text{stabilityFund}$ = WETH reserve excluded from NAV
- $\text{contractBalance}$ = GBLIN held by the contract itself (excluded from circulating supply)

### On-chain implementation

```solidity
function _calculateNAV(uint256 excludeWeth) internal view returns (uint256) {
    uint256 supply = totalSupply() - balanceOf(address(this));
    if (supply == 0) return 1 ether;
    return (_calculateTotalEthValue(excludeWeth) * 1 ether) / supply;
}
```

### Total value calculation

```solidity
function _calculateTotalEthValue(uint256 excludeWeth) internal view returns (uint256) {
    uint256 wethBal = IWETH(WETH).balanceOf(address(this));
    wethBal = wethBal > excludeWeth ? wethBal - excludeWeth : 0;
    uint256 totalEthVal = wethBal > stabilityFund ? wethBal - stabilityFund : 0;

    for (uint i = 0; i < basket.length; i++) {
        if (basket[i].token != WETH && basket[i].dynamicWeight > 0) {
            uint256 bal = IERC20(basket[i].token).balanceOf(address(this));
            if (bal > 0) totalEthVal += _convertToEth(basket[i], bal);
        }
    }
    return totalEthVal;
}
```

### Numerical example

Assume:
- Contract WETH balance: **3 ETH**
- cbBTC balance: **0.005 cbBTC** (≈ 3 ETH at current price)
- USDC balance: **2,500 USDC** (≈ 0.7 ETH)
- Stability Fund: **0.05 ETH**
- Total supply: **5 GBLIN**

$$
\text{TVL} = (3 - 0.05) + 3 + 0.7 = 6.65 \text{ ETH}
$$
$$
\text{NAV} = \frac{6.65}{5} = 1.33 \text{ ETH per GBLIN}
$$

### Cross-asset conversion (Chainlink-based)

```solidity
function _convertToEth(Asset memory _a, uint256 _amt) internal view returns (uint256) {
    uint256 pE = _getOraclePrice(WETH_ORACLE);
    uint256 pA = _getOraclePrice(_a.oracle);
    uint256 val = (_amt * pA) / pE;
    uint8 d = IERC20Metadata(_a.token).decimals();
    return d < 18 ? val * (10**(18-d)) : val / (10**(d-18));
}
```

Decimal adjustment is critical: cbBTC has 8 decimals, USDC has 6. Normalization to 18 ensures consistency with WETH.

---

## 5. Fee System and Redistribution

### The two fees

Every GBLIN purchase pays **0.10%** total, split into:

| Fee | Value | Destination |
|---|---|---|
| `FOUNDER_FEE_BPS` | 5 BPS (0.05%) | Creator wallet |
| `STABILITY_FEE_BPS` | 5 BPS (0.05%) | Stability Fund (WETH held by contract) |

```solidity
fF = (ethAmt * FOUNDER_FEE_BPS) / BPS_DENOMINATOR;
sF = (ethAmt * STABILITY_FEE_BPS) / BPS_DENOMINATOR;
```

### The Stability Fund

The `stabilityFund` is a WETH reserve held by the contract, **excluded from NAV calculation**. Its purposes:

1. Pay rewards to keepers executing rebalances (0.0001 ETH/call)
2. Cover shortfalls in case of slippage during internal swaps
3. Provide a minimum liquidity reserve

### Dynamic Reserve and Surplus Distribution

The "appropriate" reserve amount is calculated dynamically:

$$
\text{reserve} = \text{clip}\left(\frac{\text{TVL}}{1000},\ \text{floor},\ \text{ceiling}\right)
$$

```solidity
function getDynamicReserve() public view returns (uint256) {
    uint256 dynamicReserve = _calculateTotalEthValue(0) / 1000;  // 0.1% of TVL
    if (dynamicReserve < reserveFloor) return reserveFloor;       // never below 0.05 ETH
    if (dynamicReserve > reserveCeiling) return reserveCeiling;   // never above 2 ETH
    return dynamicReserve;
}
```

### The cornerstone function: `distributeYield()`

When the reserve exceeds the dynamic target, the **surplus implicitly re-enters the NAV** (because excess WETH is no longer excluded):

```solidity
function distributeYield() external {
    if (block.timestamp < lastYieldDistribution + YIELD_INTERVAL) revert TimeNotPassed();
    uint256 currentReserve = getDynamicReserve();
    if (stabilityFund <= currentReserve) revert NoExcessYield();

    uint256 excess = stabilityFund - currentReserve;
    stabilityFund = currentReserve;
    lastYieldDistribution = block.timestamp;
    emit YieldDistributed(excess);
}
```

### What this means for holders

The excess accumulated above `getDynamicReserve()` is not distributed as a dividend but **incorporated into the NAV**: every 7 days the value of each GBLIN increases proportionally to the trading volume of the period.

**Real example:**

- Basket TVL: 50 ETH → target reserve = 0.05 ETH
- Accumulated Stability Fund: 0.18 ETH
- Distributed surplus: 0.13 ETH
- Supply: 100 GBLIN
- NAV effect: **+0.0013 ETH per GBLIN** (≈ +0.1% market value in one week, derived purely from volume)

This mechanism is automatically triggered (`_autoDistributeYield()`) on every `buy`/`sell`, and can be manually called by anyone.

---

## 6. Autonomous Rebalance Mechanism

### Objective

Maintain the **ETH value of each asset** aligned with the target weight (`dynamicWeight`).

### Mathematical target

For each asset $i$:

$$
\text{TargetValue}_i = \text{TVL} \cdot \frac{\text{dynamicWeight}_i}{10000}
$$

If $\text{currentValue}_i < \text{TargetValue}_i$ → buy. Else → sell.

### Implementation: `incentivizedRebalance()`

```solidity
function incentivizedRebalance(uint256 assetIndex, bool isWethToAsset, uint256 amountToSwap) external nonReentrant
```

**Step-by-step flow:**

1. **Minimum volume check** — prevents fund drain attacks:

   ```solidity
   uint256 minSwapRequired = IWETH(WETH).balanceOf(address(this)) / 100;
   if (minSwapRequired < 0.01 ether) minSwapRequired = 0.01 ether;
   ```

2. **Weight refresh** — applies Crash Shield and redistribution in real time.

3. **Target calculation**:

   ```solidity
   uint256 targetAssetEthValue = (_calculateTotalEthValue(0) * a.dynamicWeight) / BPS_DENOMINATOR;
   uint256 currentAssetEthValue = _convertToEth(a, IERC20(a.token).balanceOf(address(this)));
   ```

4. **Direction and trade capping**:
   - If `isWethToAsset = true`: swap allowed only if `currentAssetEthValue < targetAssetEthValue`. Amount capped to required delta.
   - If `isWethToAsset = false`: swap allowed only if `currentAssetEthValue > targetAssetEthValue`.

5. **Uniswap V3 swap execution** with `minOut` calculated applying `maxInternalSlippage` (default 2%).

6. **Keeper reward**:

   ```solidity
   if (stabilityFund >= 0.0001 ether) {
       stabilityFund -= 0.0001 ether;
       IWETH(WETH).withdraw(0.0001 ether);
       (bool success, ) = payable(msg.sender).call{value: 0.0001 ether}("");
   }
   ```

### Numerical rebalance example

**State:**
- TVL: 10 ETH
- Effective cbBTC: 4.0 ETH (40%)
- Effective WETH: 5.0 ETH
- Effective USDC: 1.0 ETH (10%)
- `dynamicWeight` cbBTC = 4500 BPS → target = 4.5 ETH

**Calculation:**

$$
\Delta = 4.5 - 4.0 = 0.5 \text{ ETH}
$$

A keeper calls `incentivizedRebalance(0, true, 0.5 ether)`. The contract buys 0.5 ETH of cbBTC with minimum slippage, restoring target allocation. The keeper earns 0.0001 ETH.

---

## 7. The Crash Shield: Mathematics of Protection

This is the mechanism that distinguishes GBLIN from simple peer-to-peer indexes.

### Logic

For each asset, the contract tracks the **recent price peak** (`peakPrice`). If current price drops 20% or more from the peak, the **dynamic weight is cut to 20% of baseWeight**:

$$
\text{drawdown} = \frac{\text{peakPrice} - \text{currentPrice}}{\text{peakPrice}}
$$

$$
\text{if drawdown} > 20\% \implies \text{dynamicWeight} = \text{baseWeight} \cdot 0.2
$$

```solidity
uint256 drawdown = ((peakPrice - currentPrice) * BPS_DENOMINATOR) / peakPrice;

if (drawdown > CRASH_THRESHOLD_BPS) {
    uint256 newWeight = (a.baseWeight * SLASH_MULTIPLIER) / BPS_DENOMINATOR;
    totalSlashedWeight += (a.baseWeight - newWeight);
    a.dynamicWeight = newWeight;
    emit CrashShieldActivated(a.token, newWeight);
}
```

The "slashed" weight is **redistributed to healthy assets**:

```solidity
if (totalSlashedWeight > 0) {
    if (healthyStableCount > 0) {
        uint256 extra = totalSlashedWeight / healthyStableCount;
        for (...) basket[i].dynamicWeight += extra;
    } else if (healthyRiskCount > 0) {
        // fallback: redistribute to healthy risk assets
    }
}
```

**Redistribution priority:** first to stablecoins (USDC), then to non-WETH risk assets if no healthy stables exist.

### Peak decay

To prevent historical peaks from "trapping" an asset in permanent alert, `peakPrice` decays by **0.5% per day**:

$$
\text{peakPrice}_{t+1} = \text{peakPrice}_t \cdot (1 - 0.005 \cdot \text{daysPassed})
$$

```solidity
uint256 daysPassed = (block.timestamp - a.lastPeakUpdate) / 86400;
if (daysPassed > 0 && a.peakPrice > 0) {
    uint256 decay = (a.peakPrice * PEAK_DECAY_PER_DAY * daysPassed) / BPS_DENOMINATOR;
    a.peakPrice = (decay < a.peakPrice) ? a.peakPrice - decay : currentPrice;
}
```

If cbBTC reaches $100,000 and falls to $79,000 (-21%), the shield activates. If price stabilizes at $90,000, after ~40 days the `peakPrice` decays to ~$80,000 and the calculated drawdown returns below threshold, **automatically deactivating the shield**.

---

## 8. Historical Case Studies

### 8.1 January 2026 Crash (BTC −28%, ETH −34% in 72h)

On **January 17, 2026** the crypto market experienced a brutal correction: BTC collapsed from $108,500 to $78,000 (−28%) in three days, ETH from $4,200 to $2,770 (−34%) in the same period. The cause: cascading liquidations on perpetual exchanges following geopolitical escalation.

**Simulation: direct portfolio vs GBLIN**

Assume $10,000 invested on January 14:

**Scenario A — Direct allocation 45% BTC + 45% ETH + 10% USDC:**

| Asset | Allocation | 01/14 | 01/20 | Variation |
|---|---|---|---|---|
| BTC | $4,500 | $108,500 | $78,000 | −$1,266 |
| ETH | $4,500 | $4,200 | $2,770 | −$1,532 |
| USDC | $1,000 | $1.00 | $1.00 | $0 |
| **Total** | **$10,000** | | | **−$2,798 (−27.98%)** |

**Scenario B — Same capital in GBLIN:**

On **January 15** (day of the first −22% drop), the Crash Shield activates on BTC and ETH. Weights shift:

```
baseWeight  cbBTC  = 4500 → dynamicWeight = 900 (20%)
baseWeight  WETH   = 4500 → dynamicWeight = 900 (20%)
baseWeight  USDC   = 1000 → dynamicWeight = 1000 + (3600 + 3600) = 8200 (82%)
```

At the first post-shield rebalance, the contract **sells** part of cbBTC and WETH and **buys** USDC until basket value re-aligns.

| Asset | Post-shield allocation | 01/14 (effective) | 01/20 |
|---|---|---|---|
| cbBTC | $2,000 | $108,500 | $78,000 → $1,438 |
| WETH | $2,000 | $4,200 | $2,770 → $1,319 |
| USDC | $6,000 | $1.00 | $6,000 |
| **Total GBLIN** | $10,000 | | **$8,757 (−12.43%)** |

**Difference:** a GBLIN holder would have lost **$1,243 instead of $2,798** — savings of **55.6%** on absolute loss.

> ⚠️ The simulation assumes the rebalance is executed at the moment the shield activates. In practice, rebalance occurs when a keeper calls it or automatically on the next deposit/redemption. Actual loss depends on keeper-network reaction speed.

### 8.2 Terra/Luna Crash (May 2022)

Hypothetical case: if LUNA had been a basket asset weighted 30%, with USDC at 10%:

- May 9, 2022, 18:00 UTC: LUNA $63 → $30 (−52% in 6h).
- Recorded `peakPrice` for LUNA was ~$120 (April peak). Drawdown = (120 − 30) / 120 = **75% = 7500 BPS**.
- 7500 BPS > CRASH_THRESHOLD_BPS (2000) → Crash Shield activates immediately.
- LUNA `dynamicWeight` cut from 3000 → 600 (20%).
- The 2400 BPS recovered are redistributed to USDC.

At the next rebalance (within minutes), the contract would have **sold 80% of held LUNA at $30**, avoiding the final collapse phase (LUNA → $0.0001 within 72h).

**Mathematical result:** an initial 30% basket exposure to LUNA would have automatically reduced to 6%, with an estimated total loss of **5.4% of NAV** instead of the **30%** a passive holder would have suffered.

### 8.3 Model limitations

The Crash Shield **does not protect from:**

- **Instant crashes (>50% in few blocks)**: the shield needs a keeper to execute the rebalance.
- **Zero-liquidity events**: if the asset's Uniswap pool collapses, the swap fails with silent `try/catch` and the rebalance does not realign weights until liquidity returns.
- **Oracle de-peg**: if Chainlink returns price 0 or stale (>24h), the asset is "amputated" (weight = 0) and NAV is calculated excluding it, but losses between event and detection remain on-book.

---

## 9. In-Kind Facility (ETF-style Mint/Redeem)

A unique GBLIN feature: minting and redeeming by depositing/receiving the basket tokens directly, **without going through swaps**. Same logic used by authorized participants of traditional ETFs.

### Advantages

1. **Zero slippage**: no Uniswap swap.
2. **Zero impact** on the market price of underlying assets.
3. **Capital efficient** for those who already hold the basket.

### `quoteMintInKind(uint256 gblinTarget)`

Calculates exact amount of each asset required to mint `gblinTarget` GBLIN:

```solidity
uint256 nav = _calculateNAV(0);
uint256 totalEthNeeded = (gblinTarget * nav) / 1 ether;
for (uint i = 0; i < basket.length; i++) {
    uint256 assetEthValue = (totalEthNeeded * basket[i].dynamicWeight) / BPS_DENOMINATOR;
    requiredAssets[i] = _convertEthToAsset(basket[i], assetEthValue);
}
```

### `mintInKind(uint256 gblinTarget)`

Executes the multi-asset deposit and mints GBLIN net of the 0.10% fee.

### `redeemInKind(uint256 gblinAmount)`

Burns GBLIN and returns the proportional share of **each basket asset** to the user. No swaps, no slippage.

```solidity
(uint256 wethShare, uint256[] memory assetShares) = _getPreBurnShares(gblinAmount, supply);
_burn(msg.sender, gblinAmount);
for (uint i = 0; i < basket.length; i++) {
    if (assetShares[i] > 0) IERC20(basket[i].token).transfer(msg.sender, assetShares[i]);
}
```

---

## 10. AI Agent Integration (Model Context Protocol)

GBLIN ships a first-class **MCP server** that turns the index into a treasury primitive for autonomous AI agents on Base. This is the only on-chain index protocol on Base mainnet listed on the official Anthropic MCP Registry.

### What the MCP server is

`@gblin-protocol/mcp-server` is a stdio-based Model Context Protocol server (Node.js) that exposes **8 tools** — 6 free (read-only or calldata-only) and 2 paid via x402 micropayments. It is **non-custodial**: it never holds keys, never signs, never broadcasts. The agent's wallet (EOA, ERC-4337, or EIP-7702) remains the sole signer.

#### Free tools

| Tool | Purpose |
|---|---|
| `get_treasury_state` | NAV in USD + basket composition + Crash Shield status |
| `quote_safe_swap` | Preview buy/sell with dynamic slippage buffer (read-only) |
| `swap_gblin_to_usdc_jit` | **Atomic GBLIN→USDC calldata for x402 invoice settlement** |
| `invest_usdc_to_gblin` | Convert USDC earnings into GBLIN treasury (MEV-safe minOut) |
| `get_governance_state` | Verify owner == 48h Timelock + pending ops (trust gating) |
| `share_skill_with_peer` | Generate a portable skill seed to onboard a peer agent, with an embedded ERC-8021 Builder Code referral |

#### Paid tools (x402 micropayments)

| Tool | Price | Purpose |
|---|---|---|
| `analyze_treasury_health` | $0.003 USDC | Balances + gas runway + rebalance recommendation |
| `find_keeper_bounty` | $0.001 USDC | **GBLIN pays you**: check for an available rebalance bounty (0.0001 ETH reward, only gas required) |

### Why this matters for x402-paying agents

Coinbase and Cloudflare's **x402** standard (HTTP 402 Payment Required) requires agents to settle USDC micropayments instantly. Holding 100% USDC means zero yield and full inflation exposure. Holding GBLIN means:

1. **Diversified upside** — basket exposure to cbBTC/WETH/USDC with Crash Shield protection.
2. **Just-In-Time settlement** — `swap_gblin_to_usdc_jit` returns ready-to-broadcast calldata that burns GBLIN, swaps the basket → WETH → USDC in a **single atomic transaction** via the contract's native `sellGBLINForToken`. No batched UserOps, no half-finished JIT.
3. **MEV protection** — `minOut` is computed on-chain with a dynamic 2.5% / 4% slippage buffer (4% during Crash Shield).
4. **Verifiable trust** — `get_governance_state` returns `owner_is_timelock: true` + `min_delay_seconds: 172800` so agents can gate trust-sensitive actions on whether admin is fully delay-enforced.

### Quick install (Claude Desktop, Windsurf, Cursor)

```json
{
  "mcpServers": {
    "gblin": {
      "command": "npx",
      "args": ["-y", "@gblin-protocol/mcp-server"]
    }
  }
}
```

### Coinbase AgentKit integration

GBLIN is natively compatible with Coinbase's `@coinbase/agentkit-model-context-protocol` extension. Once added to the agent's MCP client, all 8 GBLIN tools sit alongside AgentKit's native wallet tools and can be called atomically from the same agent loop.

```ts
import { MCPClient } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

const transport = new StdioClientTransport({
  command: "npx",
  args: ["-y", "@gblin-protocol/mcp-server"],
});
const gblinClient = new MCPClient({ name: "agentkit-agent", version: "1.0.0" });
await gblinClient.connect(transport);

// JIT a $0.50 USDC payment for an x402 invoice
const jit = await gblinClient.callTool({
  name: "swap_gblin_to_usdc_jit",
  arguments: { usdc_needed: "0.50", wallet_address: agentKitWallet.address },
});
```

### ElizaOS plugin

For agents running on **ElizaOS**, the companion package [`plugin-gblin`](https://www.npmjs.com/package/plugin-gblin) exposes three native Actions — `CHECK_GBLIN_TREASURY_HEALTH`, `INVEST_IDLE_USDC_GBLIN`, `RESCUE_USDC_FROM_GBLIN` — plus a Provider that injects live NAV + Crash Shield status into the agent context on every loop. Install with `npm install plugin-gblin` or `elizaos plugins add gblin`. Repo: [github.com/gblinproject/GBLIN_PLUGIN](https://github.com/gblinproject/GBLIN_PLUGIN).

### Zero-config discovery (`gblin-init`)

Running `npx -p @gblin-protocol/mcp-server gblin-init` drops an `AGENTS.md` treasury policy into a repository so any modern AI coding assistant (Claude Code, Cursor, Windsurf, GitHub Copilot, Codex) automatically discovers GBLIN when it works on that codebase. The command is idempotent and safe — it creates `AGENTS.md` from the canonical template if absent, or appends a clearly delimited GBLIN block without touching existing content. It runs offline via a bundled fallback template.

### GBLIN Sentinel — autonomous x402 data agent (producer side)

[GBLIN Sentinel](https://gblin-sentinel.vercel.app) is an open-source reference agent that closes the loop on the agent economy. Instead of *paying* for data (the consumer side covered by the MCP tools above), Sentinel *sells* real-time DeFi risk signals over x402 and reinvests the revenue into the GBLIN treasury. It is live proof that GBLIN works on both ends of agentic commerce: agents that earn, and agents that spend.

| Endpoint | Price | Returns |
|---|---|---|
| `/api/data/base-risk-pulse` | $0.002 USDC | Chainlink risk signal (normal / caution / risk-off) for ETH, BTC, USDC, with price-staleness and USDC-depeg checks |
| `/api/data/gblin-analytics` | $0.001 USDC | GBLIN protocol state: total supply, basket composition, stability fund, keeper availability |
| `/api/data/keeper-opps` | $0.001 USDC | Live keeper-bounty check + MCP tool reference (earn 0.0001 ETH) |
| `/api/data/risk-pulse-pro` | $0.01 USDC | **Premium**: risk signal + treasury analytics + one agent-actionable recommendation (invest / hold / reduce / defer) with confidence and suggested allocation % |

Source: [github.com/gblinproject/gblin-sentinel](https://github.com/gblinproject/gblin-sentinel) · LLM reference: [llms.txt](https://gblin-sentinel.vercel.app/llms.txt) · Manifest: [/.well-known/x402](https://gblin-sentinel.vercel.app/.well-known/x402)

### Machine-readable discovery & trust files

GBLIN publishes discovery files so agents and protocols can find, integrate, and verify it without human intervention:

- **x402 manifest** (paid endpoints, prices, chain id): [gblin.digital/.well-known/x402](https://gblin.digital/.well-known/x402)
- **LLM discovery summary** (free, no paywall): [gblin.digital/api/x402/llms.txt](https://gblin.digital/api/x402/llms.txt)
- **Agent quick start**: [gblin.digital/agents](https://gblin.digital/agents)
- **Base MCP plugin** (official integration, in review): [PR #56 on base/skills](https://github.com/base/skills/pull/56)
- **MCP Registry listing**: [`io.github.gblinproject/gblin-mcp-server`](https://registry.modelcontextprotocol.io/v0/servers?search=gblin)

### Agent-to-agent propagation & keeper income

Two ecosystem mechanisms make GBLIN spread and reward agents autonomously:

- **Skill propagation** — the `share_skill_with_peer` tool lets one agent hand another a portable JSON "skill seed" (install instructions + working example + referral code). When the new agent transacts, an [ERC-8021](https://eips.ethereum.org/EIPS/eip-8021) Builder Code (`bc_gbdo32j0`) redirects a share of the existing protocol fee to the referrer — sourced from the fee split, never added on top.
- **Keeper income** — the `find_keeper_bounty` tool / Sentinel's `keeper-opps` endpoint surface available rebalances. The caller earns **0.0001 ETH** from the stability fund using the contract's own capital, paying only gas (~$0.01 on Base). GBLIN is one of the few protocols that *pays* agents instead of charging them. Live leaderboard: [gblin.digital/keepers](https://gblin.digital/keepers).

### Repositories

| Repository | Purpose |
|---|---|
| [GBLIN-Protocol](https://github.com/gblinproject/GBLIN-Protocol) | Smart contract + this technical specification |
| [GBLIN-MCP](https://github.com/gblinproject/GBLIN-MCP) | MCP server (`@gblin-protocol/mcp-server`) — the 8 agent tools |
| [GBLIN_WEBAPP](https://github.com/gblinproject/GBLIN_WEBAPP) | Web app + x402 HTTP endpoints |
| [GBLIN_PLUGIN](https://github.com/gblinproject/GBLIN_PLUGIN) | ElizaOS plugin (`plugin-gblin`) |
| [gblin-sentinel](https://github.com/gblinproject/gblin-sentinel) | x402 data agent (producer-side reference) |
| [Whitepaper](https://github.com/gblinproject/Whitepaper) | GBLIN Whitepaper V5 |

---

## 11. Complete Function Reference

### 11.1 Buy functions

| Function | Description |
|---|---|
| `buyGBLIN(uint256 minGblinOut)` | Buy GBLIN by sending native ETH. `minGblinOut` protects from slippage. |
| `buyGBLINWithToken(bytes path, uint256 amountIn, uint256 minWethOut, uint256 minGblinOut)` | Buy GBLIN with any ERC-20, routing the swap via Uniswap V3 with a custom `path`. |
| `mintInKind(uint256 gblinTarget)` | Deposit the required amount of all basket assets and receive GBLIN. |

### 11.2 Sell functions

| Function | Description |
|---|---|
| `sellGBLIN(uint256 gblinAmount)` | Burns GBLIN and returns proportional basket share (receiving native tokens). |
| `sellGBLINForEth(uint256 gblinAmount, uint256 minEthOut)` | Burns GBLIN, internally swaps all assets to WETH, returns ETH. |
| `sellGBLINForToken(uint256 gblinAmount, address targetToken, uint24 wethToTargetFee, uint256 minTokenOut)` | Burns GBLIN, converts everything to WETH, then swaps to arbitrary `targetToken`. Used by the MCP `swap_gblin_to_usdc_jit` tool for x402 settlements. |
| `redeemInKind(uint256 gblinAmount)` | Burns GBLIN and returns each basket asset without swap. |

### 11.3 Rebalance functions

| Function | Description |
|---|---|
| `incentivizedRebalance(uint256 assetIndex, bool isWethToAsset, uint256 amountToSwap)` | Callable by anyone. Realigns asset to target weight. 0.0001 ETH reward. |
| `refreshWeights()` | Recalculates `dynamicWeight` applying Crash Shield and redistribution. Public. |

### 11.4 Yield functions

| Function | Description |
|---|---|
| `distributeYield()` | Public. Transfers Stability Fund surplus into NAV. Callable every 7 days. |
| `getDynamicReserve()` | View. Returns current target reserve in WETH. |

### 11.5 View (read-only) functions

| Function | Output |
|---|---|
| `quoteBuyGBLIN(uint256 ethAmount)` | `(gblinOut, founderFee, stabilityFee)` — buy preview. |
| `quoteSellGBLIN(uint256 gblinAmount)` | `ethOut` — full-WETH sell preview. |
| `quoteMintInKind(uint256 gblinTarget)` | Array of required assets for in-kind mint. |
| `owner()` | Current owner address (the 48h Timelock Controller). |
| `proposedAsset()` | Pending asset addition (PendingAsset struct). |

### 11.6 Governance — dual-layer 48h delay

GBLIN_V5 enforces administrative delay at **two independent layers**:

1. **External owner = OpenZeppelin TimelockController** at [`0x6aBeC8716fFeEcf7C3D6e68255b4797113E8e5Dd`](https://basescan.org/address/0x6aBeC8716fFeEcf7C3D6e68255b4797113E8e5Dd). Every `onlyOwner` call must first be scheduled on the timelock and wait `172,800 seconds` before execution. The `MIN_DELAY` is immutable; the `updateDelay` override permanently reverts.
2. **Internal asset-addition timelock** = the `proposedAsset` mini-flow inside GBLIN_V5 itself, which adds a second 48h wait specifically for new basket assets (`TIMELOCK_DURATION = 48 hours`).

Adding a new asset therefore requires **two queued 48h windows in series** before live execution.

| Function | Auth | Description |
|---|---|---|
| `proposeAsset(...)` | `onlyOwner` (timelock) | Proposes a new basket asset. Internal 48h wait starts. |
| `executeAssetAddition()` | `onlyOwner` (timelock) | Adds the proposed asset (after both timelocks). |
| `emergencyDelist(uint256 index)` | `onlyOwner` (timelock) | Sets `baseWeight = 0` for an asset. Still subject to timelock 48h. |
| `updateOracle(uint256 index, address newOracle)` | `onlyOwner` (timelock) | Updates an asset's Chainlink oracle. |
| `updateWethOracle(address)` | `onlyOwner` (timelock) | Updates WETH oracle (NAV denominator). |
| `updateMaxSlippage(uint256)` | `onlyOwner` (timelock) | Modifies maximum slippage (capped at 10%). |
| `updateReserveBounds(uint256 floor, uint256 ceiling)` | `onlyOwner` (timelock) | Modifies dynamic reserve bounds. |
| `updateFounderWallet(address)` | `onlyFounder` | Changes the wallet receiving creator fees (not subject to timelock). |
| `transferOwnership(address)` | `onlyOwner` (timelock) | Transfers ownership. Subject to timelock 48h. |
| `renounceOwnership()` | `onlyOwner` (timelock) | **Permanently renounces** ownership (`ProtocolLockedForever` event). |

Verifiable on-chain in one call via the MCP `get_governance_state` tool.

---

## 12. Security and Defenses

### 12.1 Reentrancy Guard
All stateful external functions use `nonReentrant`.

### 12.2 Sequencer Down Detection (Base L2)

```solidity
function _checkSequencer() internal view {
    (, int256 answer, uint256 startedAt, , ) = AggregatorV3Interface(SEQUENCER_FEED).latestRoundData();
    if (answer == 1 || (block.timestamp - startedAt <= 3600)) revert SequencerDown();
}
```

If the Base sequencer is down or restarted less than 1 hour ago, mint/redeem reverts.

### 12.3 Anti-Sandwich Cooldown

```solidity
if (block.timestamp < lastDepositTime[msg.sender] + 2 minutes) revert CooldownActive();
```

Prevents flash-loan sandwich attacks.

### 12.4 Anti-Drain Volume Floor

Rebalance requires minimum volume (1% of held WETH, never below 0.01 ETH) to prevent drain attacks via rewards.

### 12.5 Oracle Timeout & Asset Amputation

If an oracle has not updated for >24h or returns price ≤0, the asset is automatically "amputated" on the next `refreshWeights()`. NAV no longer considers it.

### 12.6 Anti-Dilution NAV Snapshot

```solidity
uint256 nav = _calculateNAV(exWeth);   // exclude incoming WETH
out = ((ethAmt - fF - sF) * 1 ether) / nav;
```

Prevents the deposit itself from "diluting" the price it pays.

### 12.7 Founder Fee Failsafe

If the ETH transfer to `founderWallet` fails, the amount is reconverted to WETH and added to the stability fund — **never lost**.

### 12.8 Renouncing Ownership

The owner (currently the Timelock Controller) can permanently renounce ownership. After renouncement, all `onlyOwner` functions become permanently locked. The `ProtocolLockedForever` event records this on-chain.

### 12.9 48h Timelock Controller (admin delay enforcement)

Ownership of GBLIN_V5 has been transferred to a deployed OpenZeppelin `TimelockController` at [`0x6aBeC8716fFeEcf7C3D6e68255b4797113E8e5Dd`](https://basescan.org/address/0x6aBeC8716fFeEcf7C3D6e68255b4797113E8e5Dd). Properties enforced at the contract level:

- **`MIN_DELAY` is immutable** — the `updateDelay` override permanently reverts, eliminating the rug-then-attack vector.
- **`PROPOSER_ROLE` and `CANCELLER_ROLE` are strictly separated** — the constructor reverts if any address holds both, ensuring a malicious proposer cannot cancel community-friendly cancellations.
- **`EXECUTOR_ROLE` is open** (`address(0)`) — anyone can execute a matured operation, anti-censorship.
- **`DEFAULT_ADMIN_ROLE`** is held by the timelock itself — every role/config change must itself go through the 48h delay (self-administered).
- **`GRACE_PERIOD` of 14 days** — pending operations expire if not executed in time (no zombie proposals).

This means that even if proposer keys were compromised, an attacker still cannot drain or alter the protocol without giving the community a 48-hour public window to inspect the call, raise alarms, and trigger `cancel`.

---

## 13. Audit Status

| Stage | Status |
|---|---|
| Internal review | ✅ Completed |
| Public source verification (BaseScan) | ✅ Verified |
| 48h Timelock Controller deployed and ownership transferred | ✅ Live (May 2026) |
| MCP server published on npm + Anthropic Registry | ✅ Live (May 2026) |
| External audit | 🟡 Open to community review |
| Formal verification | 🔵 Roadmap |

The contract source is **publicly verified on BaseScan** and open for inspection. Independent reviews and PRs are welcome (see [Contributing](#16-contributing)).

---

## 14. Bug Bounty & Responsible Disclosure

The GBLIN protocol welcomes responsible security research.

- **Critical bugs** (loss of user funds, contract takeover): contact `info@gblin.digital` with PoC.
- **High-severity bugs** (DoS, oracle manipulation): same channel, encrypted disclosure preferred.
- **Disclosure window**: 30 days before public disclosure.

Researchers acting in good faith will not face legal action and will be acknowledged in the next protocol update.

---

## 15. Repository Structure

```
GBLIN-Protocol/
├── README.md                  # This document — V5 Technical Specification
├── GBLIN.sol                  # Canonical contract source
├── LICENSE                    # MIT
├── SECURITY.md                # Security policy & responsible disclosure
├── CONTRIBUTING.md            # Contribution guidelines
├── CODE_OF_CONDUCT.md         # Contributor Covenant
├── CHANGELOG.md               # Version history
├── funding.json               # Funding metadata
├── audits/
│   └── README.md              # Audit reports index
├── docs/
│   ├── architecture.md        # Extended architecture notes
│   ├── deployments.md         # Deployment addresses & infrastructure
│   └── governance.md          # Governance model
└── .github/
    ├── PULL_REQUEST_TEMPLATE.md
    └── ISSUE_TEMPLATE/
        ├── bug_report.md
        └── feature_request.md
```

Companion repository: [`gblinproject/GBLIN-MCP`](https://github.com/gblinproject/GBLIN-MCP) — Model Context Protocol server (`@gblin-protocol/mcp-server`).

---

## 16. Contributing

Contributions are welcome. Please:

1. Open an issue describing the change before submitting a PR.
2. Sign commits with GPG when possible.
3. For documentation fixes, submit a PR directly.
4. For security disclosures, see [Bug Bounty](#14-bug-bounty--responsible-disclosure).

---

## 17. References & Further Reading

1. GBLIN Whitepaper V5 — [PDF](https://github.com/gblinproject/Whitepaper/raw/main/GBLIN_WHITE_PAPER_V5.pdf)
2. Adams, H. et al. *Uniswap V3 Core Whitepaper* (2021) — [uniswap.org](https://uniswap.org/whitepaper-v3.pdf)
3. Egorov, M. *StableSwap — Curve Whitepaper* (2019) — [curve.fi](https://curve.fi/files/stableswap-paper.pdf)
4. Chainlink Price Feeds Documentation — [docs.chain.link](https://docs.chain.link/data-feeds)
5. OpenZeppelin Contracts — [github.com/OpenZeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts)
6. Base L2 Sequencer Feed — [docs.base.org](https://docs.base.org/)
7. EIP-2612: ERC-20 Permit — [eips.ethereum.org/EIPS/eip-2612](https://eips.ethereum.org/EIPS/eip-2612)
8. Model Context Protocol specification — [modelcontextprotocol.io](https://modelcontextprotocol.io)
9. x402 payment standard — [x402.org](https://www.x402.org/) and [docs.cdp.coinbase.com/x402](https://docs.cdp.coinbase.com/x402/welcome)
10. Coinbase AgentKit MCP extension — [`@coinbase/agentkit-model-context-protocol`](https://www.npmjs.com/package/@coinbase/agentkit-model-context-protocol)

---

## 18. Technical Glossary

| Term | Meaning |
|---|---|
| **NAV** | Net Asset Value — value in ETH of 1 GBLIN |
| **BPS** | Basis Points — 1 BPS = 0.01% |
| **Drawdown** | Percentage decline from recent peak |
| **Crash Shield** | Automatic weight reduction on assets in >20% drawdown |
| **Slash** | Cut of dynamic weight (to 20% of baseWeight) |
| **Peak Decay** | Automatic reduction of recorded peak price (0.5%/day) |
| **In-Kind** | Mint/redeem with real assets instead of ETH |
| **Stability Fund** | WETH reserve to pay keepers and cover shortfalls |
| **Keeper** | Any address calling `incentivizedRebalance()` for the reward |
| **Sequencer** | Base's L2 sequencer; if down, the contract freezes |
| **TVL** | Total Value Locked — sum of all basket asset values in ETH |
| **MCP** | Model Context Protocol — open standard for AI-agent tools, governed by Linux Foundation |
| **MCP Registry** | The official Anthropic registry of MCP servers ([registry.modelcontextprotocol.io](https://registry.modelcontextprotocol.io)) |
| **x402** | Open payment standard (HTTP 402 Payment Required), co-founded by Coinbase + Cloudflare under the Linux Foundation |
| **JIT swap** | Just-In-Time atomic swap GBLIN→USDC, used by agents to settle x402 invoices in a single transaction |
| **Timelock Controller** | OpenZeppelin contract that enforces a 48h delay on every admin action (current owner of GBLIN_V5) |
| **MIN_DELAY** | The immutable 48h enforcement constant on the Timelock Controller |

---

## Disclaimer

This report is a technical descriptive document of the deployed contract code. It does not constitute financial advice. Holding GBLIN involves typical DeFi risks: code bugs, oracle failures, market risk on underlying assets, liquidity risk on Uniswap pools. Always verify the contract before interacting.

**Verify the contract on BaseScan:** [`0x38DcDB3A381677239BBc652aed9811F2f8496345`](https://basescan.org/address/0x38DcDB3A381677239BBc652aed9811F2f8496345)
**Verify the timelock owner:** [`0x6aBeC8716fFeEcf7C3D6e68255b4797113E8e5Dd`](https://basescan.org/address/0x6aBeC8716fFeEcf7C3D6e68255b4797113E8e5Dd)
**Verify the MCP listing:** [registry.modelcontextprotocol.io/v0/servers?search=gblin](https://registry.modelcontextprotocol.io/v0/servers?search=gblin)

---

*Document version: 1.2 — June 2026*
*Maintained by: GBLIN Protocol*
*License: [MIT](./LICENSE)*
