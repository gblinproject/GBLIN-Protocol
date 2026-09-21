// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title ISwapAdapter
/// @author GBLIN Protocol
/// @notice Swap venue used by the periphery zap.
interface ISwapAdapter {
    /// @notice Swaps `amountIn` of `tokenIn`, pulled from the caller, into at least `minOut` of `tokenOut` sent to the
    ///         caller.
    /// @dev `data` is venue-specific routing data and must be valid for both directions of the pair.
    /// @param tokenIn Token sold.
    /// @param tokenOut Token bought.
    /// @param amountIn Amount of `tokenIn` pulled from the caller.
    /// @param minOut Minimum amount of `tokenOut`.
    /// @param data Venue-specific routing data.
    /// @return out Amount of `tokenOut` sent to the caller.
    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut, bytes calldata data)
        external
        returns (uint256 out);
}
