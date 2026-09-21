// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISwapAdapter} from "../interfaces/ISwapAdapter.sol";
import {IV3SwapRouter} from "../interfaces/external/IV3SwapRouter.sol";
import {IUniswapV3Factory} from "../interfaces/external/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "../interfaces/external/IUniswapV3Pool.sol";

/// @title Uniswap V3 adapter with a TWAP guard
/// @author GBLIN Protocol
/// @notice Swap adapter for the GBLIN vault. Before every swap the pool's current tick is compared with its average
///         tick over `twapWindow` seconds; a difference above `maxTickDeviation` ticks (one tick is 0.01%) refuses the
///         swap. A price pushed within the same block moves the current tick but not the average, so the swap is
///         refused, and so is a swap in a pool without history for the window. Stateless, holds nothing between calls.
/// @dev `data` is `abi.encode(uint24 fee)`, the same in both directions.
/// @custom:security-contact info@gblin.digital
contract UniswapV3Adapter is ISwapAdapter {
    using SafeERC20 for IERC20;

    /// @notice Uniswap V3 SwapRouter02.
    address public immutable router;
    /// @notice Factory of the router's pools.
    address public immutable factory;
    /// @notice Averaging window in seconds.
    uint32 public immutable twapWindow;
    /// @notice Largest accepted difference between the current and the average tick.
    uint24 public immutable maxTickDeviation;

    /// @notice A constructor parameter is zero.
    error InvalidParameters();
    /// @notice The router has no code.
    error InvalidRouter();
    /// @notice The router returned zero output.
    error NothingDelivered();
    /// @notice No pool exists for the pair and fee.
    error NoPool();
    /// @notice The current tick is too far from the average tick.
    error PriceOffTwap(int24 spot, int24 twapTick);

    /// @param _router Uniswap V3 SwapRouter02.
    /// @param _twapWindow Averaging window in seconds; positive.
    /// @param _maxTickDeviation Largest accepted tick difference; positive.
    constructor(address _router, uint32 _twapWindow, uint24 _maxTickDeviation) {
        if (_twapWindow == 0 || _maxTickDeviation == 0) revert InvalidParameters();
        if (_router.code.length == 0) revert InvalidRouter();
        router = _router;
        factory = IV3SwapRouter(_router).factory();
        twapWindow = _twapWindow;
        maxTickDeviation = _maxTickDeviation;
    }

    /// @notice Current tick and average tick of the pool for `tokenIn`/`tokenOut` at `fee`.
    /// @dev Reverts if the pool does not exist or has no observations for the window. The average rounds toward
    ///      negative infinity.
    function spotAndTwap(address tokenIn, address tokenOut, uint24 fee)
        public
        view
        returns (int24 spot, int24 twapTick)
    {
        address pool = IUniswapV3Factory(factory).getPool(tokenIn, tokenOut, fee);
        if (pool == address(0)) revert NoPool();
        (, spot,,,,,) = IUniswapV3Pool(pool).slot0();
        uint32[] memory ago = new uint32[](2);
        ago[0] = twapWindow;
        ago[1] = 0;
        (int56[] memory tc,) = IUniswapV3Pool(pool).observe(ago);
        int56 delta = tc[1] - tc[0];
        twapTick = int24(delta / int56(uint56(twapWindow)));
        if (delta < 0 && (delta % int56(uint56(twapWindow)) != 0)) twapTick--;
    }

    /// @dev Reverts with `PriceOffTwap` if the current tick is more than `maxTickDeviation` from the average tick.
    function _checkTwap(address tokenIn, address tokenOut, uint24 fee) internal view {
        (int24 spot, int24 twapTick) = spotAndTwap(tokenIn, tokenOut, fee);
        int24 diff = spot > twapTick ? spot - twapTick : twapTick - spot;
        if (uint24(diff) > maxTickDeviation) revert PriceOffTwap(spot, twapTick);
    }

    /// @inheritdoc ISwapAdapter
    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut, bytes calldata data)
        external
        override
        returns (uint256 out)
    {
        uint24 fee = abi.decode(data, (uint24));
        _checkTwap(tokenIn, tokenOut, fee);
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).forceApprove(router, amountIn);

        out = IV3SwapRouter(router)
            .exactInputSingle(
                IV3SwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: fee,
                recipient: msg.sender,
                amountIn: amountIn,
                amountOutMinimum: minOut,
                sqrtPriceLimitX96: 0
            })
            );

        IERC20(tokenIn).forceApprove(router, 0);
        if (out == 0) revert NothingDelivered();
    }
}
