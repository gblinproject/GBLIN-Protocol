// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IUniswapV3Pool
/// @notice Uniswap V3 pool, as far as the adapter reads it.
interface IUniswapV3Pool {
    /// @notice Current state of the pool.
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        );

    /// @notice Cumulative tick and liquidity values at each of `secondsAgos` before now.
    /// @param secondsAgos Offsets in seconds before the current block time.
    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s);
}
