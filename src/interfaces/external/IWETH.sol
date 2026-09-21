// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IWETH
/// @notice Wrapped ether, as far as the GBLIN contracts use it.
interface IWETH {
    /// @notice Wraps the ETH sent with the call into as many units for the caller.
    function deposit() external payable;

    /// @notice Unwraps `amount` units of the caller into ETH.
    /// @param amount Units to unwrap.
    function withdraw(uint256 amount) external;

    /// @notice Units held by `account`.
    /// @param account Account.
    function balanceOf(address account) external view returns (uint256);

    /// @notice Moves `amount` units from the caller to `to`.
    /// @param to Receiver.
    /// @param amount Units to move.
    function transfer(address to, uint256 amount) external returns (bool);

    /// @notice Allows `spender` to move up to `amount` units of the caller.
    /// @param spender Spender.
    /// @param amount Allowance.
    function approve(address spender, uint256 amount) external returns (bool);
}
