# Deployments

## Base Mainnet

### V6 (current)

| Field | Value |
|---|---|
| Address | [`0x36C81d7E1966310F305eA637e761Cf77F90852f0`](https://basescan.org/address/0x36C81d7E1966310F305eA637e761Cf77F90852f0) |
| Deployment date | 2026-06 |
| Deployer | (see BaseScan) |
| Verified | ✅ |
| Compiler | Solidity 0.8.20 (viaIR) |
| Optimizer | Enabled (low runs, viaIR) |

### Initial Basket

| Asset | Address | Weight | Pool Fee | Oracle |
|---|---|---|---|---|
| cbBTC | `0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf` | 45% | 0.05% | `0x07DA0E54543a844a80ABE69c8A12F22B3aA59f9D` |
| WETH | `0x4200000000000000000000000000000000000006` | 45% | — | `0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70` |
| USDC | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` | 10% | 0.05% | `0x7e860098F58bBFC8648a4311b374B1D669a2bc6B` |

### Infrastructure

| Component | Address |
|---|---|
| Uniswap V3 Router | `0x2626664c2603336E57B271c5C0b26F421741e481` |
| Base L2 Sequencer Feed | `0xBCF85224fc0756B9Fa45aA7892530B47e10b6433` |
| Aerodrome Pool (V6) | `0x6Ac18D5e90278D2477027B5769EFb2fF0711FFbB` |
| Uniswap V3 Pool (V6) | `0xAb305c45F4E42A73909a49a6775e3f7782239dAE` |
| Aerodrome Pool V5 (deprecated) | `0x7dcd4f5bcdae0546c84dab54401a93ad6e92ae1b` |

## Deprecated Versions

| Version | Address | Status |
|---|---|---|
| V5 | `0x38DcDB3A381677239BBc652aed9811F2f8496345` | Superseded by V6 (2026-06); migration via web app |
| V4 | `0xED334B4CDaFCAe6D42bb9A57DE565fD3e9640a50` | Deprecated 2026-04-03 |
| V3 | — | Deprecated |
| V2 | — | Deprecated |
| V1 | — | Deprecated |

## Verification

To verify the bytecode matches the source:

```bash
forge verify-contract \
  --chain base \
  --watch \
  0x36C81d7E1966310F305eA637e761Cf77F90852f0 \
  contracts/GBLIN_V6.sol:GBLIN_GlobalBalancedLiquidityIndex
```
