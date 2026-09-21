// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IFillAgent
/// @author GBLIN Protocol
/// @notice Fill agent of the GBLIN vault: bids through `bid` without paying at once. The vault leaves the fill open,
///         counts the agent's balances of the fill's two tokens in NAV, and closes the fill with `close` before any
///         other call that moves value.
/// @dev The vault decides from balances of its own whether a swap is under way, so `swapActive` is published for
///      readers rather than relied upon by the vault.
interface IFillAgent {
    /// @notice Sends every unit of the two tokens of the open fill back to the vault.
    /// @dev Reverts only while a swap has taken part of the sold token without delivering its pro rata part of the
    ///      bought token; a token that refuses the transfer stays with the agent, out of NAV, until it can be sent
    ///      back.
    /// @return buyToken Token bought.
    /// @return sellToken Token sold.
    /// @return bought Amount of `buyToken` returned.
    /// @return sold Amount of `sellToken` that left the fill.
    function close() external returns (address buyToken, address sellToken, uint256 bought, uint256 sold);

    /// @notice True while a swap has taken part of the sold token without delivering its pro rata part of the bought
    ///         token.
    function swapActive() external view returns (bool);
}
