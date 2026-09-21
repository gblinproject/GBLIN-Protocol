// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IAerodromePoolFactory
/// @notice Aerodrome pool factory, as far as the adapter reads it.
interface IAerodromePoolFactory {
    /// @notice Pool of `tokenA` and `tokenB` of the given type; zero if it does not exist.
    /// @param tokenA One token of the pair.
    /// @param tokenB The other token of the pair.
    /// @param stable True for the stable pool type.
    function getPool(address tokenA, address tokenB, bool stable) external view returns (address pool);
}
