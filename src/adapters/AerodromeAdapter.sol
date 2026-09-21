// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISwapAdapter} from "../interfaces/ISwapAdapter.sol";
import {IAerodromeRouter} from "../interfaces/external/IAerodromeRouter.sol";
import {IAerodromePoolFactory} from "../interfaces/external/IAerodromePoolFactory.sol";
import {IAerodromePool} from "../interfaces/external/IAerodromePool.sol";

/// @title Aerodrome adapter with a TWAP guard
/// @author GBLIN Protocol
/// @notice Swap adapter for the GBLIN vault. On every hop, before the swap, the pool's spot output is compared with its
///         time-weighted output over the last `twapGranularity` observations (one every 30 minutes on Aerodrome); a gap
///         above `maxDeviationBps` refuses the swap. Both outputs are measured with a probe of a thousandth of the
///         amount, so the size of the trade does not enter the comparison. Stateless, holds nothing between calls.
/// @dev `data` is `abi.encode(Route[])`. A route stored in one direction is reversed when used in the other, so the
///      same data serves both directions.
/// @custom:security-contact info@gblin.digital
contract AerodromeAdapter is ISwapAdapter {
    using SafeERC20 for IERC20;

    uint256 private constant BPS = 10_000;
    /// @notice Aerodrome router.
    address public immutable router;
    /// @notice Number of pool observations averaged.
    uint256 public immutable twapGranularity;
    /// @notice Largest accepted gap between spot and time-weighted output (bps).
    uint256 public immutable maxDeviationBps;

    /// @notice A constructor parameter is zero or out of range.
    error InvalidParameters();
    /// @notice The router has no code.
    error InvalidRouter();
    /// @notice The router returned zero output.
    error NothingDelivered();
    /// @notice The route is empty or does not connect `tokenIn` to `tokenOut`.
    error BadRoute();
    /// @notice No pool exists for a hop.
    error NoPool();
    /// @notice A hop's spot output is too far from its time-weighted output.
    error PriceOffTwap(uint256 spot, uint256 twapOut);

    /// @param _router Aerodrome router.
    /// @param _twapGranularity Observations averaged; positive.
    /// @param _maxDeviationBps Largest accepted gap in bps; positive and below 10000.
    constructor(address _router, uint256 _twapGranularity, uint256 _maxDeviationBps) {
        if (_twapGranularity == 0 || _maxDeviationBps == 0 || _maxDeviationBps >= BPS) revert InvalidParameters();
        if (_router.code.length == 0) revert InvalidRouter();
        router = _router;
        twapGranularity = _twapGranularity;
        maxDeviationBps = _maxDeviationBps;
    }

    /// @notice Spot and time-weighted output of hop `r` for `units` in; a zero factory means the router's default
    ///         factory.
    function spotAndTwap(IAerodromeRouter.Route memory r, uint256 units)
        public
        view
        returns (uint256 spot, uint256 twapOut)
    {
        return _spotAndTwap(r, units, r.factory == address(0) ? IAerodromeRouter(router).defaultFactory() : r.factory);
    }

    /// @notice Probe used by the guard for `amountIn`: a thousandth, or the whole amount if that is zero.
    function probeAmount(uint256 amountIn) public pure returns (uint256 s) {
        s = amountIn / 1000;
        if (s == 0) s = amountIn;
    }

    /// @dev Spot and time-weighted output of hop `r` for `amountIn`, through factory `f`.
    function _spotAndTwap(IAerodromeRouter.Route memory r, uint256 amountIn, address f)
        internal
        view
        returns (uint256 spot, uint256 twapOut)
    {
        address pool = IAerodromePoolFactory(f).getPool(r.from, r.to, r.stable);
        if (pool == address(0)) revert NoPool();
        spot = IAerodromePool(pool).getAmountOut(amountIn, r.from);
        twapOut = IAerodromePool(pool).quote(r.from, amountIn, twapGranularity);
    }

    /// @dev Reverts with `PriceOffTwap` if any hop's spot output is more than `maxDeviationBps` from its time-weighted
    ///      output, probing each hop with the previous hop's spot output.
    function _checkTwap(IAerodromeRouter.Route[] memory routes, uint256 amountIn) internal view {
        uint256 amt = probeAmount(amountIn);
        address defaultFactoryAddress = IAerodromeRouter(router).defaultFactory();
        for (uint256 i = 0; i < routes.length; ++i) {
            (uint256 spot, uint256 twapOut) = _spotAndTwap(
                routes[i], amt, routes[i].factory == address(0) ? defaultFactoryAddress : routes[i].factory
            );
            uint256 diff = spot > twapOut ? spot - twapOut : twapOut - spot;
            if (twapOut == 0 || (diff * BPS) / twapOut > maxDeviationBps) revert PriceOffTwap(spot, twapOut);
            amt = spot;
        }
    }

    /// @inheritdoc ISwapAdapter
    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut, bytes calldata data)
        external
        override
        returns (uint256 out)
    {
        IAerodromeRouter.Route[] memory routes = abi.decode(data, (IAerodromeRouter.Route[]));

        if (routes.length == 0) revert BadRoute();
        if (routes[0].from != tokenIn) {
            uint256 n = routes.length;
            IAerodromeRouter.Route[] memory inv = new IAerodromeRouter.Route[](n);
            for (uint256 i = 0; i < n; ++i) {
                IAerodromeRouter.Route memory r = routes[n - 1 - i];
                inv[i] = IAerodromeRouter.Route({from: r.to, to: r.from, stable: r.stable, factory: r.factory});
            }
            routes = inv;
        }
        if (routes[0].from != tokenIn) revert BadRoute();
        if (routes[routes.length - 1].to != tokenOut) revert BadRoute();
        _checkTwap(routes, amountIn);
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).forceApprove(router, amountIn);

        uint256[] memory amounts =
            IAerodromeRouter(router).swapExactTokensForTokens(amountIn, minOut, routes, msg.sender, block.timestamp);

        IERC20(tokenIn).forceApprove(router, 0);
        out = amounts[amounts.length - 1];
        if (out == 0) revert NothingDelivered();
    }
}
