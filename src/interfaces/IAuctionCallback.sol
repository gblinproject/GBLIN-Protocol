// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IAuctionCallback
/// @author GBLIN Protocol
/// @notice Implemented by contracts that bid in the GBLIN auction with a callback.
interface IAuctionCallback {
    /// @notice Called by the vault during `bid`, after `amountOut` of `tokenOut` has been sent to the bidder and before
    ///         `amountIn` of `tokenIn` is pulled from it. The bidder must have approved the vault for `amountIn`.
    /// @param tokenIn Token the vault is about to pull.
    /// @param amountIn Amount the vault is about to pull.
    /// @param tokenOut Token the vault has sent.
    /// @param amountOut Amount the vault has sent.
    /// @param data Data the bidder passed to `bid`.
    function onAuctionFill(address tokenIn, uint256 amountIn, address tokenOut, uint256 amountOut, bytes calldata data)
        external;
}
