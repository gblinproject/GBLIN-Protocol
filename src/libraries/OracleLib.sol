// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {AggregatorV3Interface} from "../interfaces/external/AggregatorV3Interface.sol";
import {IChainlinkAggregator} from "../interfaces/external/IChainlinkAggregator.sol";

/// @title OracleLib
/// @author GBLIN Protocol
/// @notice Chainlink feed reads and conversions of the GBLIN vault.
/// @dev Reads never revert on a broken feed: `price` returns zero and `age` returns the maximum, and callers decide.
library OracleLib {
    /// @notice The two feeds do not have the same decimals.
    error ScaleMismatch();

    /// @dev Tolerance for an `updatedAt` slightly ahead of the block time.
    uint256 internal constant FUTURE_GRACE = 2 minutes;

    /// @notice Reverts unless feeds `a` and `b` have the same decimals.
    function requireSameScale(address a, address b) internal view {
        if (AggregatorV3Interface(a).decimals() != AggregatorV3Interface(b).decimals()) revert ScaleMismatch();
    }

    /// @notice True unless the feed's aggregator exposes bounds and `p` is not strictly inside them.
    /// @dev Chainlink aggregators stop at `minAnswer`/`maxAnswer`; an answer at a bound is not a market price.
    ///      A feed that does not expose the bounds passes.
    function withinBounds(address o, int256 p) internal view returns (bool) {
        (bool ok, bytes memory d) = o.staticcall(abi.encodeWithSelector(IChainlinkAggregator.aggregator.selector));
        if (!ok || d.length < 32) return true;
        address agg = abi.decode(d, (address));
        (ok, d) = agg.staticcall(abi.encodeWithSelector(IChainlinkAggregator.minAnswer.selector));
        if (!ok || d.length < 32) return true;
        int256 mn = abi.decode(d, (int256));
        (ok, d) = agg.staticcall(abi.encodeWithSelector(IChainlinkAggregator.maxAnswer.selector));
        if (!ok || d.length < 32) return true;
        int256 mx = abi.decode(d, (int256));
        return p > mn && p < mx;
    }

    /// @notice Seconds since the feed's last update; `type(uint256).max` if the feed reverts, answers a non-positive or
    ///         bounded price, or reports an update in the future.
    function age(address o) internal view returns (uint256) {
        try AggregatorV3Interface(o).latestRoundData() returns (uint80, int256 p, uint256, uint256 updatedAt, uint80) {
            if (p <= 0 || updatedAt == 0) return type(uint256).max;
            if (updatedAt > block.timestamp + FUTURE_GRACE) return type(uint256).max;
            if (!withinBounds(o, p)) return type(uint256).max;
            return block.timestamp > updatedAt ? block.timestamp - updatedAt : 0;
        } catch {
            return type(uint256).max;
        }
    }

    /// @notice The feed's answer, or zero if it is older than `timeout`, non-positive, bounded, in the future or
    ///         reverts.
    function price(address o, uint256 timeout) internal view returns (uint256) {
        try AggregatorV3Interface(o).latestRoundData() returns (uint80, int256 p, uint256, uint256 updatedAt, uint80) {
            if (p <= 0 || updatedAt == 0) return 0;
            if (updatedAt > block.timestamp + FUTURE_GRACE) return 0;
            if (block.timestamp > updatedAt && block.timestamp - updatedAt > timeout) return 0;
            if (!withinBounds(o, p)) return 0;
            return uint256(p);
        } catch {
            return 0;
        }
    }

    /// @notice Converts `amt` of `token` into wei of ETH (`intoEth`) or wei of ETH into units of `token`, at feed
    ///         prices.
    /// @dev `d` is the token's decimals as stored at listing, so the token is never called. Returns zero if either
    ///      price is unusable. WETH converts one to one. Rounds down.
    function convert(
        address token,
        uint8 d,
        address oracle,
        uint256 amt,
        address weth,
        address wethOracle,
        uint256 timeout,
        bool intoEth
    ) internal view returns (uint256) {
        if (amt == 0) return 0;
        if (token == weth) return amt;
        uint256 pE = price(wethOracle, timeout);
        uint256 pA = price(oracle, timeout);
        if (pE == 0 || pA == 0) return 0;
        if (intoEth) return d < 18 ? (amt * pA * (10 ** (18 - d))) / pE : (amt * pA) / (pE * (10 ** (d - 18)));
        return d < 18 ? (amt * pE) / (pA * (10 ** (18 - d))) : (amt * pE * (10 ** (d - 18))) / pA;
    }

    /// @notice True if the feed exposes a non-zero `aggregator()`, as Chainlink proxies do.
    function hasAggregator(address o) internal view returns (bool) {
        (bool ok, bytes memory d) = o.staticcall(abi.encodeWithSelector(IChainlinkAggregator.aggregator.selector));
        return ok && d.length >= 32 && abi.decode(d, (address)) != address(0);
    }
}
