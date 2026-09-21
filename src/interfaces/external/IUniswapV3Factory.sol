// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IUniswapV3Factory
/// @notice Uniswap V3 factory, as far as the adapter reads it.
interface IUniswapV3Factory {
    /// @notice Pool of `tokenA` and `tokenB` at `fee`; zero if it does not exist.
    /// @param tokenA One token of the pair.
    /// @param tokenB The other token of the pair.
    /// @param fee Fee tier in hundredths of a bip.
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}
