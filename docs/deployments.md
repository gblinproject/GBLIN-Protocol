# Deployments

## Base mainnet (chain id 8453) — vault in service

| Contract | Address | Creation |
|---|---|---|
| `UniswapV3Adapter` | [`0x062654Bf9b5Bd88b84D7861a8f22ba94dECd9d3F`](https://basescan.org/address/0x062654Bf9b5Bd88b84D7861a8f22ba94dECd9d3F) | [`0x7bb42836…`](https://basescan.org/tx/0x7bb42836bf356378a277c9e1300284d4d2c334f8e7eac2942ebf9225dec04a3b), block 51563242 |
| `SequencerSentinel` | [`0x9F13C5c46a864183e1c57Ec02837fe5B980D3F67`](https://basescan.org/address/0x9F13C5c46a864183e1c57Ec02837fe5B980D3F67) | [`0xc56b7caf…`](https://basescan.org/tx/0xc56b7caff8ed5a8253c2050c540818dd1af9e8a54ea96df7938fe9a735da6632), block 51563247 |
| `GBLIN` | [`0xc2181d975c05c8c724b334bcED0764c0b86B1D53`](https://basescan.org/address/0xc2181d975c05c8c724b334bcED0764c0b86B1D53) | [`0x5419f2da…`](https://basescan.org/tx/0x5419f2da2a9eb58539453efe76515791ce549c4ce31a1cd0c696200c0d78a666), block 51563253 |
| `GBLINLens` | [`0xfCFea8027019E8551A1f09AD91532471F5D26f61`](https://basescan.org/address/0xfCFea8027019E8551A1f09AD91532471F5D26f61) | [`0x91020839…`](https://basescan.org/tx/0x910208390ab0d4d10697d03841708093007aa70898edf99c47f21ffb65f649d5), block 51563262 |
| `GBLINZap` | [`0x0E9D6Ceb6D313b021622C121Cda9C62e86e60200`](https://basescan.org/address/0x0E9D6Ceb6D313b021622C121Cda9C62e86e60200) | [`0xf4c0cf8d…`](https://basescan.org/tx/0xf4c0cf8d3fd2d23e42a0bd9a57efdbc337c567c93d258ce0a17c6323a7a94a03), block 51563269 |
| `GblinAuctionOrder` | [`0x156Ffd19819e02d9809cED8fa1416EDCD31ddaB9`](https://basescan.org/address/0x156Ffd19819e02d9809cED8fa1416EDCD31ddaB9) | [`0x7fe708f7…`](https://basescan.org/tx/0x7fe708f7644f809736357142ffc0b0b3a4ca6cbd29dcb9e57bd8620863749052), block 51616023 |
| `CowFillAgent` | [`0x0f4307A5Eb7D33d04Cb68fb0bA4d47a56C7E2fc8`](https://basescan.org/address/0x0f4307A5Eb7D33d04Cb68fb0bA4d47a56C7E2fc8) | [`0xff9c3fa0…`](https://basescan.org/tx/0xff9c3fa0ac2e37d683ceb71cc883d373c3d0b06b17d305e2de85bb7e3e7b4afd), block 51616036 |

Compiler: Solidity 0.8.37, `via_ir`, optimizer enabled with 1 run, EVM version `cancun`, `cbor_metadata = false`, `bytecode_hash = "none"`. Sources verified on Sourcify (full match, creation and runtime) and on Basescan. The sources in this repository and the library files under `lib/` are the ones the verification was made with. `GblinAuctionOrder` and `CowFillAgent` were deployed after the launch; a build of this repository reproduces the runtime of all seven contracts, immutables aside.

Constructor arguments: `GblinAuctionOrder(vault, lens)`; `CowFillAgent(vault, settlement, composableCoW, orderHandler)` with the CoW Protocol settlement `0x9008D19f58AAbD9eD0D60971565AA8510560ab41`, `ComposableCoW` `0xfdaFc9d1902f4e0b84f65F49f244b32b31013b74` and the order generator above.

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
| Fill agent | none (zero address) — set after the launch, see below |

### Changes since the launch

| Change | Transaction |
|---|---|
| Fill agent set to `CowFillAgent` (`setAddress(6, 0x0f4307A5Eb7D33d04Cb68fb0bA4d47a56C7E2fc8)`) | [`0xf06a5aaf…`](https://basescan.org/tx/0xf06a5aafc638a7fec40e0c365cb2e24eda7031423e4b8eeda3780d4e3f4d66a3), block 51616061 |
| Conditional order registered with `ComposableCoW` for row 0 (cbBTC) | [`0xaa12c6b5…`](https://basescan.org/tx/0xaa12c6b589d5f2d79ba674479969e124f0287d90c4d020af731f9ac404fa6065), block 51616080 |
| Conditional order registered with `ComposableCoW` for row 2 (USDC) | [`0x675a6d3e…`](https://basescan.org/tx/0x675a6d3e91f3364f3827a5510f042bc486189c8aa32f75b5dde19f27f1d50de8), block 51616093 |
| Both orders above removed: their `appData` gave the hooks too little gas for the vault in service | [`0xd0bdefe3…`](https://basescan.org/tx/0xd0bdefe35254ba213779eaa02f1eb31b6ca0773f5a48df3fb007340a6bb72dfb), block 51619359; [`0xa71496d7…`](https://basescan.org/tx/0xa71496d7be46a0e8d91ee08a6aa5b03a64146516f10eb93f453a132f8f3962dd), block 51619371 |
| Conditional order registered for row 0 (cbBTC), current | [`0x9ac6a05e…`](https://basescan.org/tx/0x9ac6a05e5dd8b904e7e981660f4be8e7e1f6b8d6271a9a1b9f6d7f9885ae4792), block 51619383 |
| Conditional order registered for row 2 (USDC), current | [`0xe6c0342d…`](https://basescan.org/tx/0xe6c0342d351a27b7dc87191aaabd2c61b278f61e1198438394f3be6962a8555b), block 51619395 |

Each conditional order uses `GblinAuctionOrder` as handler, the row index as salt and a five-minute bucket. Its static input carries the two `appData` hashes of the row — one for the side on which the vault buys the asset, one for the side on which it sells it. Each `appData` document carries the pre-hook `openFill(row, side)` on the fill agent with a gas limit of 1,200,000 and the post-hook `refreshWeights()` on the vault with 700,000, and is registered with the CoW Protocol order book. The first registration gave the hooks 600,000 and 300,000: on the vault in service `openFill` uses about 822,000 gas and `refreshWeights` with a fill to close about 420,000, so the pre-hook ran out of gas inside the hooks trampoline, which ignores a failing hook, and the order book rejected the signature. The limits are what a solver reserves; only the gas used is spent.

| Row | Order id (`keccak256(abi.encode(params))`) | `appData`, vault buys | `appData`, vault sells |
|---|---|---|---|
| 0 (cbBTC) | `0xdf7d1a6b8322073b65703984360115827a24b0a878b42955e44287d864f6b8f0` | `0x9787a156235886f83fd0941b2b8847f35a011f3aea19ad9e19517f35a5fd5b6e` | `0xffa3df1f7858acd7be9b840afab564bd481fba255a6b9005db6b2344e14899df` |
| 2 (USDC) | `0x2cb967d8ab6ecaed30bbccc291c63480d7dff0ddb1f0b634409e1d67f12feb48` | `0xe8793fae38acbfc00432d8d3eaa455e3405b41e9b836921ec3089e81972caeba` | `0x7556318001887d62acd04d25d03f4a32e135d7f4f7b6918d29179df3ded7671b` |

### Ownership

| | |
|---|---|
| Owner | `0x6aBeC8716fFeEcf7C3D6e68255b4797113E8e5Dd` (48-hour timelock) |
| Pending owner | none |
| Acceptance | operation `0x1873b690cb95ce706938a223da20047db73a49e7b1ab23021665e5b6502a9c27` on the timelock, executed on 2026-09-22 at 21:01 UTC in transaction `0x366dc55dfe1fc3a1eb662a245ed7f5e6b54c68a0621124eafe5cf14188a2503c` (block 51660727) |

The `SequencerSentinel` is owned by the same timelock and has no pending owner; its acceptance, operation `0x10f3299fd0a5313a3146f4577946b599fb1f25a304c428e5e1c57a51fe17a4b7`, executed in transaction `0xe4f4842a682ff3d9b89b10cbc0de878ed01893aefa88d21228fe6700b17df165` (block 51660741). The sentinel's guardian is `0x30590c0D05c26562d7296CE3D927d3418d2e6dcA`, which also holds the canceller role on the timelock.

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
| First fill agent | `0xb78d74642E32e86D1d96330D047C6245a2bA7D5E` | Deployed with the vault and never connected; superseded by `CowFillAgent` above. Source verified on Sourcify and Basescan |

Neither previous contract is read by the application, the MCP server or the agent endpoints. They remain live: there is no function to disable them.

## Verification

```bash
forge build
cast code 0xc2181d975c05c8c724b334bcED0764c0b86B1D53 --rpc-url https://mainnet.base.org
jq -r .deployedBytecode.object out/GBLIN.sol/GBLIN.json
```

The two runtimes are identical except for the immutable values written at deployment.
