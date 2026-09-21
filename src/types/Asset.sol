// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice A row of the GBLIN basket.
/// @dev Fields:
///      token, oracle: the asset and its USD price feed;
///      decimals: the token's decimals, read once at listing;
///      isStable: slow-updating feed and a peg the shield watches;
///      delisted: weights forced to zero, balance still owned by the holders;
///      baseWeight: governance weight in bps; dynamicWeight: weight after the crash shield;
///      peakPrice, lastPeakUpdate, slowPeakPrice, slowLastPeakUpdate: the shield's fast and slow decaying peaks;
///      lastObservedPrice, ewmaVolBps: the shield's volatility estimate;
///      shielded: the shield is active on this row;
///      pegPrice: price at listing for a stable asset, zero otherwise.
struct Asset {
    address token;
    uint8 decimals;
    address oracle;
    bool isStable;
    bool delisted;
    uint256 baseWeight;
    uint256 dynamicWeight;
    uint256 peakPrice;
    uint256 lastPeakUpdate;
    uint256 slowPeakPrice;
    uint256 slowLastPeakUpdate;
    uint256 lastObservedPrice;
    uint256 ewmaVolBps;
    bool shielded;
    uint256 pegPrice;
}
