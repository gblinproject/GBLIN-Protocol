// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IAerodromePool
/// @notice Aerodrome pool, as far as the adapter reads it.
interface IAerodromePool {
    /// @notice Output of a swap of `amountIn` of `tokenIn` at the current reserves.
    /// @param amountIn Input amount.
    /// @param tokenIn Input token.
    function getAmountOut(uint256 amountIn, address tokenIn) external view returns (uint256);

    /// @notice Time-weighted output of a swap of `amountIn` of `tokenIn` over the last `granularity` observations.
    /// @param tokenIn Input token.
    /// @param amountIn Input amount.
    /// @param granularity Number of observations averaged.
    function quote(address tokenIn, uint256 amountIn, uint256 granularity) external view returns (uint256 amountOut);
}
