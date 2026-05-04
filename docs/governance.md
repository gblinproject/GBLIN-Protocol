# Governance

GBLIN Protocol uses **minimal governance with timelock-protected admin actions**. There is no DAO token, no voting, no off-chain proposal system. Governance is intentionally constrained to operational maintenance.

## Roles

| Role | Address (current) | Powers |
|---|---|---|
| `owner` | (see contract) | Asset proposal/addition, oracle updates, slippage/reserve bounds, ownership transfer/renouncement |
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

### Hard caps

| Action | Cap |
|---|---|
| `MAX_NEW_ASSET_WEIGHT` | 30% (3000 BPS) |
| `updateMaxSlippage` max | 10% (1000 BPS) |
| `reserveBounds` | floor ≤ ceiling enforced |

### What governance CANNOT do

- ❌ Move user funds.
- ❌ Mint GBLIN to arbitrary addresses.
- ❌ Modify fees (`FOUNDER_FEE_BPS`, `STABILITY_FEE_BPS` are constants).
- ❌ Pause the contract.
- ❌ Upgrade the contract (non-upgradeable by design).

## Renouncement

The owner can permanently lock the protocol by calling `renounceOwnership()`. After this:
- All `onlyOwner` functions revert forever.
- The basket becomes immutable.
- Oracle updates become impossible.
- The `ProtocolLockedForever` event is emitted on-chain.

This is the **end-state goal** of the protocol once the basket is mature and oracle redundancy is established.

## Founder Fee

The founder fee (0.05% of every mint) goes to `founderWallet`. The wallet can be updated only by the wallet itself (`onlyFounder`), preventing the owner from redirecting it.

If the ETH transfer to `founderWallet` fails, the fee is reconverted to WETH and added to the stability fund — never lost.
