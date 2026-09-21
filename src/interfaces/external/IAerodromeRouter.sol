// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IAerodromeRouter
/// @notice Aerodrome router, as far as the adapter calls it.
interface IAerodromeRouter {
    /// @notice One hop of a route.
    struct Route {
        address from;
        address to;
        bool stable;
        address factory;
    }

    /// @notice Swaps `amountIn` of the first token of `routes` through every hop.
    /// @param amountIn Input amount.
    /// @param amountOutMin Minimum output of the last hop.
    /// @param routes Hops, in order.
    /// @param to Receiver of the output.
    /// @param deadline Time after which the swap reverts.
    /// @return amounts Amount entering the first hop followed by the output of every hop.
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    /// @notice Pool factory used when a hop does not name one.
    function defaultFactory() external view returns (address);
}
