// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IV3SwapRouter
/// @notice Uniswap V3 functions of the Uniswap SwapRouter02, as far as the adapter calls them.
interface IV3SwapRouter {
    /// @notice Parameters of a single-pool exact-input swap.
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Swaps `amountIn` of `tokenIn` for as much `tokenOut` as possible in one pool.
    /// @param params Swap parameters.
    /// @return amountOut Amount of `tokenOut` received by the recipient.
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);

    /// @notice Uniswap V3 factory of the router's pools.
    function factory() external view returns (address);
}
