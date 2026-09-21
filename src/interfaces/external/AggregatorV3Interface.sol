// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title AggregatorV3Interface
/// @notice Chainlink price or sequencer uptime feed, as far as the GBLIN contracts read it.
interface AggregatorV3Interface {
    /// @notice Latest round of the feed.
    /// @return roundId Round identifier.
    /// @return answer Answer of the round.
    /// @return startedAt Time the round started; for a sequencer uptime feed, the time of the last status change.
    /// @return updatedAt Time the answer was last updated.
    /// @return answeredInRound Round in which the answer was computed.
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    /// @notice Decimals of the answer.
    function decimals() external view returns (uint8);
}
