# Deployments

## Base mainnet (chain id 8453) — vault in service

| Contract | Address | Creation |
|---|---|---|
| `UniswapV3Adapter` | [`0x062654Bf9b5Bd88b84D7861a8f22ba94dECd9d3F`](https://basescan.org/address/0x062654Bf9b5Bd88b84D7861a8f22ba94dECd9d3F) | [`0x7bb42836…`](https://basescan.org/tx/0x7bb42836bf356378a277c9e1300284d4d2c334f8e7eac2942ebf9225dec04a3b), block 51563242 |
| `SequencerSentinel` | [`0x9F13C5c46a864183e1c57Ec02837fe5B980D3F67`](https://basescan.org/address/0x9F13C5c46a864183e1c57Ec02837fe5B980D3F67) | [`0xc56b7caf…`](https://basescan.org/tx/0xc56b7caff8ed5a8253c2050c540818dd1af9e8a54ea96df7938fe9a735da6632), block 51563247 |
| `GBLIN` | [`0xc2181d975c05c8c724b334bcED0764c0b86B1D53`](https://basescan.org/address/0xc2181d975c05c8c724b334bcED0764c0b86B1D53) | [`0x5419f2da…`](https://basescan.org/tx/0x5419f2da2a9eb58539453efe76515791ce549c4ce31a1cd0c696200c0d78a666), block 51563253 |
| `GBLINLens` | [`0xfCFea8027019E8551A1f09AD91532471F5D26f61`](https://basescan.org/address/0xfCFea8027019E8551A1f09AD91532471F5D26f61) | [`0x91020839…`](https://basescan.org/tx/0x910208390ab0d4d10697d03841708093007aa70898edf99c47f21ffb65f649d5), block 51563262 |
| `GBLINZap` | [`0x0E9D6Ceb6D313b021622C121Cda9C62e86e60200`](https://basescan.org/address/0x0E9D6Ceb6D313b021622C121Cda9C62e86e60200) | [`0xf4c0cf8d…`](https://basescan.org/tx/0xf4c0cf8d3fd2d23e42a0bd9a57efdbc337c567c93d258ce0a17c6323a7a94a03), block 51563269 |
| `CowFillAgent` (not connected) | [`0xb78d74642E32e86D1d96330D047C6245a2bA7D5E`](https://basescan.org/address/0xb78d74642E32e86D1d96330D047C6245a2bA7D5E) | [`0x369870c0…`](https://basescan.org/tx/0x369870c0a137da13696053688f635c200234ad90364ea225cdd1789369669839), block 51563275 |

Compiler: Solidity 0.8.37, `via_ir`, optimizer enabled with 1 run, EVM version `cancun`, `cbor_metadata = false`, `bytecode_hash = "none"`. Sources verified on Sourcify (full match, creation and runtime) and on Basescan. The sources in this repository and the library files under `lib/` are the ones the verification was made with.

### Basket

| Row | Asset | Address | Target weight | Oracle (Chainlink) |
|---|---|---|---|---|
| 0 | cbBTC | `0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf` | 45% | `0x07DA0E54543a844a80ABE69c8A12F22B3aA59f9D` |
| 1 | WETH | `0x4200000000000000000000000000000000000006` | 45% | `0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70` |
| 2 | USDC | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` | 10% | `0x7e860098F58bBFC8648a4311b374B1D669a2bc6B` |

### Parameters at launch

Read through `GBLINLens` at the addresses above.

| Group | Values |
|---|---|
| Mint fees | protocol 5 bps, stability 5 bps |
| In-kind fee | floor 50 bps, deviation tax up to 150 bps |
| Management fee | 50 bps per year |
| Minimum deposit | none |
| Feed ages | pricing 7,200 s, trading 1,800 s |
| Redemption cooldown | 20 s |
| Auction band | opens above 700 bps of drift, closes at or below 175 bps |
| Auction curve | start discount 100 bps, cap 25 bps, ramp 3,600 s |
| Volatility update interval | 3,600 s |
| Listing delay | 86,400 s |
| Basket size cap | 20 rows |
| Shield | base threshold 1,500 bps, volatility multiplier 5,000, recovery band 800 bps, slash multiplier 2,000, fast peak decay 50 bps/day, slow peak decay 15 bps/day, full-slash drawdown 3,000 bps, crash threshold bounds 1,500–5,000 bps, peg band 200 bps |
| Fee recipient | `0x9FFa542E369C53af62380296092EC669f329a9ee` |
| Sequencer feed | the `SequencerSentinel` above, wrapping `0xBCF85224fc0756B9Fa45aA7892530B47e10b6433` |
| ETH price feed | `0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70` |
| Fill agent | none (zero address) |

### Ownership

| | |
|---|---|
| Owner | `0x9FFa542E369C53af62380296092EC669f329a9ee` (deployer) |
| Pending owner | `0x6aBeC8716fFeEcf7C3D6e68255b4797113E8e5Dd` (timelock) |
| Scheduled acceptance | operation `0x1873b690cb95ce706938a223da20047db73a49e7b1ab23021665e5b6502a9c27` on the timelock, executable from 2026-09-22 16:16:31 UTC by anyone, within the 14-day grace period |

The `SequencerSentinel` has the same owner and pending owner; its acceptance is operation `0x10f3299fd0a5313a3146f4577946b599fb1f25a304c428e5e1c57a51fe17a4b7`. The sentinel's guardian is `0x30590c0D05c26562d7296CE3D927d3418d2e6dcA`, which also holds the canceller role on the timelock.

## Timelock

| Field | Value |
|---|---|
| Address | [`0x6aBeC8716fFeEcf7C3D6e68255b4797113E8e5Dd`](https://basescan.org/address/0x6aBeC8716fFeEcf7C3D6e68255b4797113E8e5Dd) |
| Minimum delay | 172,800 s (48 hours), immutable |
| Grace period | 14 days |
| Executor | open (any address) |
| Proposer | `0x9FFa542E369C53af62380296092EC669f329a9ee` |
| Canceller | `0x30590c0D05c26562d7296CE3D927d3418d2e6dcA` |

## Previous deployments

| Contract | Address | Status |
|---|---|---|
| Previous index contract | `0x36C81d7E1966310F305eA637e761Cf77F90852f0` | Superseded. Owned by the timelock. Holders redeem in kind or migrate through the web application. Source: [`legacy/GBLIN_V6.sol`](../legacy/GBLIN_V6.sol) |
| Older index contract | `0x38DcDB3A381677239BBc652aed9811F2f8496345` | Superseded. Source: [`legacy/GBLIN_V5.sol`](../legacy/GBLIN_V5.sol) |
| `0xED334B4CDaFCAe6D42bb9A57DE565fD3e9640a50` and earlier | — | Deprecated |

Neither previous contract is read by the application, the MCP server or the agent endpoints. They remain live: there is no function to disable them.

## Verification

```bash
forge build
cast code 0xc2181d975c05c8c724b334bcED0764c0b86B1D53 --rpc-url https://mainnet.base.org
jq -r .deployedBytecode.object out/GBLIN.sol/GBLIN.json
```

The two runtimes are identical except for the immutable values written at deployment.
