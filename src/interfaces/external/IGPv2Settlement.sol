// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IGPv2Settlement
/// @notice CoW Protocol settlement contract, as far as the fill agent reads it.
interface IGPv2Settlement {
    /// @notice EIP-712 domain separator under which orders are signed.
    function domainSeparator() external view returns (bytes32);

    /// @notice Contract that pulls the sold tokens of the settled orders.
    function vaultRelayer() external view returns (address);
}
