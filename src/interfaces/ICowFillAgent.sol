// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title ICowFillAgent
/// @author GBLIN Protocol
/// @notice The fill agent as its order generator and the public read it: the open fill, and the registration of the
///         auction orders with CoW Protocol.
interface ICowFillAgent {
    /// @notice The vault opened a fill of `sellAmount` of `sellToken` for at least `minBuyAmount` of `buyToken`.
    event FillOpened(address indexed sellToken, address indexed buyToken, uint256 sellAmount, uint256 minBuyAmount);
    /// @notice Closing could not send `amount` of `token` back to the vault; it stays here until `rescue` succeeds.
    event ReturnFailed(address indexed token, uint256 amount);
    /// @notice A fill left open in an earlier block was cleared with `emergencyClose`.
    event FillForceClosed(address indexed sellToken, address indexed buyToken, uint256 sellReturned, uint256 bought);
    /// @notice A conditional order for basket row `index` was registered with CoW Protocol.
    event AuctionOrderRegistered(uint256 indexed index, bytes32 indexed singleOrderHash);
    /// @notice A conditional order was removed from CoW Protocol.
    event AuctionOrderRemoved(bytes32 indexed singleOrderHash);

    /// @notice The caller is not allowed, or the order is used outside the block in which the fill was opened.
    error Unauthorized();
    /// @notice A fill is open.
    error FillOpen();
    /// @notice A swap has taken part of the sold token without delivering the bought one.
    error SwapActive();
    /// @notice The digest does not belong to the order carried by the signature.
    error OrderRejected(uint256 code);

    /// @notice Token the open fill sells; zero when no fill is open.
    function sellToken() external view returns (address);
    /// @notice Token the open fill buys; zero when no fill is open.
    function buyToken() external view returns (address);
    /// @notice Amount of `sellToken` the vault sent for the open fill.
    function sellAmount() external view returns (uint256);
    /// @notice Least amount of `buyToken` for the whole `sellAmount`.
    function minBuyAmount() external view returns (uint256);
    /// @notice Block in which the open fill was opened; zero when no fill is open.
    function openBlock() external view returns (uint256);

    /// @notice Opens a fill of the auction of the vault's `basket[index]`. Anyone can call; meant as the pre-hook of
    ///         the agent's order.
    /// @param index Basket row.
    /// @param vaultBuysAsset As in the vault's `bid`.
    /// @return amountIn Least amount of the input the solvers must deliver for the whole output.
    /// @return amountOut Output received from the vault.
    function openFill(uint256 index, bool vaultBuysAsset) external returns (uint256 amountIn, uint256 amountOut);

    /// @notice Registers with CoW Protocol the conditional order that keeps basket row `index` on target. Only the
    ///         vault's owner.
    /// @param index Basket row.
    /// @param appDataVaultBuys `appData` of the orders in which the vault buys the asset; its document carries the
    ///                         pre-hook `openFill(index, true)`.
    /// @param appDataVaultSells `appData` of the orders in which the vault sells the asset; its document carries the
    ///                          pre-hook `openFill(index, false)`.
    /// @param bucketSeconds Length of the time bucket within which the generated order does not change.
    /// @return singleOrderHash Identifier of the conditional order, for `unregister`.
    function register(uint256 index, bytes32 appDataVaultBuys, bytes32 appDataVaultSells, uint32 bucketSeconds)
        external
        returns (bytes32 singleOrderHash);

    /// @notice Removes a conditional order from CoW Protocol. Only the vault's owner.
    /// @param singleOrderHash Identifier returned by `register`.
    function unregister(bytes32 singleOrderHash) external;

    /// @notice Clears a fill left open in an earlier block and sends its two tokens back to the vault. Anyone can
    ///         call; it cannot fail.
    function emergencyClose() external;

    /// @notice Sends the whole balance of `token` to the vault while no fill is open.
    /// @param token Token to send.
    function rescue(address token) external;
}
