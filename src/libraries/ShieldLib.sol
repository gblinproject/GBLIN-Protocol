// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Asset} from "../types/Asset.sol";

/// @title ShieldLib
/// @author GBLIN Protocol
/// @notice Crash shield and in-kind fee arithmetic of the GBLIN vault.
/// @dev For every row the shield keeps a fast and a slow decaying price peak. When the drawdown from the higher of the
///      two exceeds a volatility-adjusted threshold, the row's weight is cut in proportion to how far the drawdown has
///      moved from the threshold toward `fullSlashDrawdownBps`. The weight removed goes, in equal parts, to stable rows
///      that are at their peg and not shielded themselves; without such rows it stays in WETH, the implicit remainder
///      of the weights. A row whose feed has no usable price loses its whole weight until the price returns.
library ShieldLib {
    uint256 private constant BPS = 10_000;

    /// @dev Shield parameters, copied from the vault's storage.
    struct Params {
        uint256 baseCrashThresholdBps;
        uint256 crashVolMultiplier;
        uint256 recoveryBandBps;
        uint256 slashMultiplier;
        uint256 peakDecayPerDayBps;
        uint256 slowPeakDecayPerDayBps;
        uint256 fullSlashDrawdownBps;
        uint256 minCrashBps;
        uint256 maxCrashBps;
        uint256 pegBandBps;
        bool updateVol;
    }

    /// @notice Emitted when the shield activates on a row.
    event CrashShieldActivated(address indexed token, uint256 drawdownBps, uint256 thresholdBps);
    /// @notice Emitted when a row recovers within the recovery band.
    event CrashShieldDeactivated(address indexed token);

    /// @notice Recomputes every row's dynamic weight from `prices` (zero for a feed without a usable price).
    /// @dev The volatility estimate is an EWMA of absolute price changes, updated only when `p.updateVol` is set.
    ///      The shield activates above the threshold and deactivates only below `recoveryBandBps`.
    function refresh(Asset[] storage basket, uint256[] memory prices, Params memory p) internal {
        uint256 totalSlashed;
        uint256 healthyStable;
        uint256 n = basket.length;

        for (uint256 i = 0; i < n; ++i) {
            Asset storage a = basket[i];
            a.dynamicWeight = a.baseWeight;
            if (a.baseWeight == 0) continue;

            uint256 cp = prices[i];
            if (cp == 0) {
                totalSlashed += a.baseWeight;
                a.dynamicWeight = 0;
                continue;
            }

            if (p.updateVol) {
                if (a.lastObservedPrice > 0) {
                    uint256 diff = cp > a.lastObservedPrice ? cp - a.lastObservedPrice : a.lastObservedPrice - cp;
                    uint256 inst = (diff * BPS) / a.lastObservedPrice;
                    a.ewmaVolBps = (inst * 3 + a.ewmaVolBps * 7) / 10;
                }
                a.lastObservedPrice = cp;
            }

            _decayPeaks(a, cp, p);

            uint256 ddFast = a.peakPrice > cp ? ((a.peakPrice - cp) * BPS) / a.peakPrice : 0;
            uint256 ddSlow = a.slowPeakPrice > cp ? ((a.slowPeakPrice - cp) * BPS) / a.slowPeakPrice : 0;
            uint256 dd = ddFast > ddSlow ? ddFast : ddSlow;

            uint256 thr = p.baseCrashThresholdBps + (a.ewmaVolBps * p.crashVolMultiplier) / BPS;
            if (thr < p.minCrashBps) thr = p.minCrashBps;
            if (thr > p.maxCrashBps) thr = p.maxCrashBps;
            if (thr > p.fullSlashDrawdownBps) thr = p.fullSlashDrawdownBps;

            if (!a.shielded && dd > thr) {
                a.shielded = true;
                emit CrashShieldActivated(a.token, dd, thr);
            } else if (a.shielded && dd < p.recoveryBandBps) {
                a.shielded = false;
                emit CrashShieldDeactivated(a.token);
            }

            if (a.shielded) {
                uint256 sev;
                if (dd >= p.fullSlashDrawdownBps) {
                    sev = BPS;
                } else if (dd > thr && p.fullSlashDrawdownBps > thr) {
                    sev = ((dd - thr) * BPS) / (p.fullSlashDrawdownBps - thr);
                }
                uint256 keepBps = BPS - (sev * (BPS - p.slashMultiplier)) / BPS;
                uint256 nw = (a.baseWeight * keepBps) / BPS;
                totalSlashed += (a.baseWeight - nw);
                a.dynamicWeight = nw;
            }

            if (a.isStable && !a.shielded && _atPeg(a, cp, p.pegBandBps)) ++healthyStable;
        }

        if (totalSlashed > 0 && healthyStable > 0) {
            uint256 extra = totalSlashed / healthyStable;
            for (uint256 i = 0; i < n; ++i) {
                if (
                    basket[i].isStable && !basket[i].shielded && basket[i].dynamicWeight > 0
                        && _atPeg(basket[i], prices[i], p.pegBandBps)
                ) basket[i].dynamicWeight += extra;
            }
        }
    }

    /// @notice In-kind mint fee in bps for a deposit of `ethValue` into a row worth `cur` with a target of `target`.
    /// @dev `floorBps` if the deposit brings the row closer to its target; otherwise the floor plus `taxBps` scaled by
    ///      the average deviation over the deposit, relative to the target (capped at the target). A row with no target
    ///      pays the floor plus the full tax.
    function inKindFee(uint256 target, uint256 cur, uint256 ethValue, uint256 floorBps, uint256 taxBps)
        internal
        pure
        returns (uint256)
    {
        if (target == 0) return floorBps + taxBps;
        uint256 diffBefore = cur > target ? cur - target : target - cur;
        uint256 valueAfter = cur + ethValue;
        uint256 diffAfter = valueAfter > target ? valueAfter - target : target - valueAfter;
        if (diffAfter < diffBefore) return floorBps;
        uint256 average = (diffBefore + diffAfter) / 2;
        if (average > target) average = target;
        return floorBps + (taxBps * average) / target;
    }

    /// @dev True if the row has no peg or `cp` is within `bandBps` of it.
    function _atPeg(Asset storage a, uint256 cp, uint256 bandBps) private view returns (bool) {
        if (a.pegPrice == 0) return true;
        uint256 diff = cp > a.pegPrice ? cp - a.pegPrice : a.pegPrice - cp;
        return (diff * BPS) / a.pegPrice <= bandBps;
    }

    /// @dev Decays both peaks by their daily rate for every full day since their last update, then raises them to `cp`.
    function _decayPeaks(Asset storage a, uint256 cp, Params memory p) private {
        uint256 dP = (block.timestamp - a.lastPeakUpdate) / 1 days;
        if (dP > 0 && a.peakPrice > 0) {
            uint256 dec = (a.peakPrice * p.peakDecayPerDayBps * dP) / BPS;
            a.peakPrice = dec < a.peakPrice ? a.peakPrice - dec : cp;
            a.lastPeakUpdate = block.timestamp;
        }
        if (cp > a.peakPrice) {
            a.peakPrice = cp;
            a.lastPeakUpdate = block.timestamp;
        }

        uint256 dS = (block.timestamp - a.slowLastPeakUpdate) / 1 days;
        if (dS > 0 && a.slowPeakPrice > 0) {
            uint256 dec = (a.slowPeakPrice * p.slowPeakDecayPerDayBps * dS) / BPS;
            a.slowPeakPrice = dec < a.slowPeakPrice ? a.slowPeakPrice - dec : cp;
            a.slowLastPeakUpdate = block.timestamp;
        }
        if (cp > a.slowPeakPrice) {
            a.slowPeakPrice = cp;
            a.slowLastPeakUpdate = block.timestamp;
        }
    }
}
