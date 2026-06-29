# Governance

GBLIN Protocol uses **minimal governance with timelock-protected admin actions**. There is no DAO token, no voting, no off-chain proposal system. Governance is intentionally constrained to operational maintenance.

## Roles

| Role | Address (current) | Powers |
|---|---|---|
| `owner` (held by 48h Timelock) | [`0x6aBeC8…E8e5Dd`](https://basescan.org/address/0x6aBeC8716fFeEcf7C3D6e68255b4797113E8e5Dd) | Asset proposal/addition, oracle updates, fee tuning (≤ hard cap), slippage / crash / bounty / cooldown parameters (all bounded), ownership transfer. **Cannot renounce** (removed in V6) |
| `founderWallet` | (see contract) | Receives founder fee (0.05% of mints), can update its own address |

## Constraints

### Timelock (48 hours)

All asset additions go through a mandatory 48-hour timelock:

```
proposeAsset(...)  →  wait 48h  →  executeAssetAddition()
```

This gives the community a window to:
- Review the proposed asset's oracle reliability.
- Verify Uniswap V3 liquidity for the asset.
- Object publicly if necessary.

### Immutable hard caps

Every governable parameter is bounded **in code** by an immutable constant — governance can tune inside the envelope, never break it:

| Parameter | Immutable hard cap |
|---|---|
| Total fee (`founderFeeBps + stabilityFeeBps`) | ≤ 5% (`HARD_MAX_FEE_BPS = 500`) — current soft cap `maxFeeBps` = 0.5%, live fees 0.1% |
| Internal slippage (`maxInternalSlippage`) | ≤ 20% (`HARD_MAX_SLIPPAGE_BPS = 2000`) — live 5.5% |
| Crash band (`minCrashBps`/`maxCrashBps`) | 3% – 90% (`HARD_MAX_CRASH_BPS = 9000`) |
| Keeper bounty | ≤ 2% (`HARD_MAX_INCENTIVE_BPS = 200`) |
| New asset weight (`MAX_NEW_ASSET_WEIGHT`) | ≤ 30% (3000 BPS) |
| Basket size | ≤ 50 assets (`HARD_MAX_BASKET_SIZE`) |
| Oracle timeout | ≤ 30 days (`HARD_MAX_ORACLE_TIMEOUT`) |
| Min deposit | ≤ 1 ETH (`HARD_MAX_MIN_DEPOSIT`) |

> The legacy `reserveBounds` (yield-drip floor/ceiling) was **removed in V6** — yield is now distributed instantly on every fee split.

### What governance CANNOT do

- ❌ Move user funds or mint GBLIN to arbitrary addresses.
- ❌ Exceed any immutable hard cap above (e.g. fees > 5%, slippage > 20%, bounty > 2%).
- ❌ Raise fees beyond the cap — fees are tunable via `setFees`, but only within `maxFeeBps` (≤ 5% hard cap); live fees are 0.05% founder + 0.05% stability.
- ❌ Redirect the founder fee (only `founderWallet` itself can, via `onlyFounder`).
- ❌ Pause the contract.
- ❌ Upgrade the contract (non-upgradeable by design).
- ❌ Renounce ownership — `renounceOwnership` was **removed in V6** (see below).

## Perpetual, hard-capped governance (no renounce)

V6 **removed `renounceOwnership`** by design. Trust does **not** come from throwing the keys away — it comes from two things that hold forever:

1. **The 48h Timelock Controller** owns the contract ([`0x6aBeC8…E8e5Dd`](https://basescan.org/address/0x6aBeC8716fFeEcf7C3D6e68255b4797113E8e5Dd)). Every `onlyOwner` action must be scheduled, wait 48 hours in public, then be executed — giving the community time to inspect and react.
2. **The immutable hard caps** above, which no admin action can ever exceed.

Renouncing would have frozen the basket and made oracles/router **un-repointable** — meaning the protocol could not survive a deprecated DEX router or a failing Chainlink feed over a multi-year horizon. Keeping bounded, timelocked governance lets GBLIN adapt its infrastructure for decades **without ever being able to rug holders**.

## Founder Fee

The founder fee (0.05% of every mint) goes to `founderWallet`. The wallet can be updated only by the wallet itself (`onlyFounder`), preventing the owner from redirecting it.

If the ETH transfer to `founderWallet` fails, the fee is reconverted to WETH and added to the stability fund — never lost.
