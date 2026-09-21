// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IChainlinkAggregator
/// @notice Chainlink feed proxy and the aggregator behind it, as far as the answer bounds are read.
interface IChainlinkAggregator {
    /// @notice Aggregator currently behind the feed proxy.
    function aggregator() external view returns (address);

    /// @notice Lowest answer the aggregator can report.
    function minAnswer() external view returns (int192);

    /// @notice Highest answer the aggregator can report.
    function maxAnswer() external view returns (int192);
}
