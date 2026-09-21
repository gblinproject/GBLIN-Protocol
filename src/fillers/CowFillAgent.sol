// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IGBLIN} from "../interfaces/IGBLIN.sol";
import {IAuctionCallback} from "../interfaces/IAuctionCallback.sol";
import {IFillAgent} from "../interfaces/IFillAgent.sol";
import {ICowFillAgent} from "../interfaces/ICowFillAgent.sol";
import {IGPv2Settlement} from "../interfaces/external/IGPv2Settlement.sol";
import {IComposableCoW} from "../interfaces/external/IComposableCoW.sol";
import {IConditionalOrder} from "../interfaces/external/IConditionalOrder.sol";
import {GPv2OrderLib} from "../libraries/GPv2OrderLib.sol";
import {GblinAuctionOrder} from "./GblinAuctionOrder.sol";

/// @title CoW Protocol fill agent for GBLIN auctions
/// @author GBLIN Protocol
/// @notice Bids in the vault's auction without paying at once, and lets CoW Protocol solvers settle the fill in the
///         same block through an EIP-1271 order at the auction price or better. When the vault closes the fill, every
///         unit of the two tokens goes back to it, including any surplus the solvers delivered. The orders themselves
///         are conditional orders of the CoW Protocol programmatic order framework, registered here by the vault's
///         owner and posted by the framework's watch-tower.
/// @dev One fill, inside one CoW settlement: the order's pre-hook calls `openFill`, which bids with no input limit; the
///      vault sends its output here, calls `onAuctionFill` and, because the caller is its fill agent, leaves the fill
///      open instead of pulling the input. The settlement then verifies the order through `isValidSignature`, which
///      this contract forwards to `ComposableCoW` and, through it, to the order generator that checks the order
///      against the open fill; the settlement pulls the sold token through the vault relayer and delivers the bought
///      token here; the post-hook calls the vault's `refreshWeights`, which calls `close`. Any later call of the vault
///      that moves value closes the fill as well. The fill pattern follows the trusted fillers of Reserve Protocol
///      (MIT). The agent has no owner and keeps no balance between fills.
/// @custom:security-contact info@gblin.digital
contract CowFillAgent is ICowFillAgent, IFillAgent, IAuctionCallback {
    /// @notice The vault this agent serves.
    address public immutable VAULT;
    /// @notice CoW Protocol vault relayer, the only spender of the sold token.
    address public immutable RELAYER;
    /// @notice EIP-712 domain separator of the CoW Protocol settlement contract.
    bytes32 public immutable DOMAIN_SEPARATOR;
    /// @notice The `ComposableCoW` contract the orders are registered with.
    IComposableCoW public immutable COMPOSABLE_COW;
    /// @notice The order generator every registered conditional order points to.
    GblinAuctionOrder public immutable ORDER_HANDLER;

    /// @inheritdoc ICowFillAgent
    address public sellToken;
    /// @inheritdoc ICowFillAgent
    address public buyToken;
    /// @inheritdoc ICowFillAgent
    uint256 public sellAmount;
    /// @inheritdoc ICowFillAgent
    uint256 public minBuyAmount;
    /// @inheritdoc ICowFillAgent
    uint256 public openBlock;

    /// @param vault The GBLIN vault.
    /// @param settlement The CoW Protocol settlement contract.
    /// @param composableCoW The `ComposableCoW` contract.
    /// @param orderHandler The order generator, built for `vault`.
    constructor(address vault, address settlement, address composableCoW, address orderHandler) {
        VAULT = vault;
        RELAYER = IGPv2Settlement(settlement).vaultRelayer();
        DOMAIN_SEPARATOR = IGPv2Settlement(settlement).domainSeparator();
        COMPOSABLE_COW = IComposableCoW(composableCoW);
        ORDER_HANDLER = GblinAuctionOrder(orderHandler);
    }

    /// @inheritdoc ICowFillAgent
    function openFill(uint256 index, bool vaultBuysAsset) external returns (uint256 amountIn, uint256 amountOut) {
        return IGBLIN(VAULT).bid(index, vaultBuysAsset, type(uint256).max, 0, hex"01");
    }

    /// @notice Called by the vault during the agent's bid, once the output has arrived: records the fill and lets the
    ///         CoW Protocol relayer spend the output.
    /// @param tokenIn Token the solvers must deliver.
    /// @param amountIn Least amount of `tokenIn` for the whole output.
    /// @param tokenOut Token received from the vault.
    /// @param amountOut Amount of `tokenOut` received.
    function onAuctionFill(address tokenIn, uint256 amountIn, address tokenOut, uint256 amountOut, bytes calldata)
        external
    {
        if (msg.sender != VAULT) revert Unauthorized();
        if (openBlock != 0) revert FillOpen();
        sellToken = tokenOut;
        buyToken = tokenIn;
        sellAmount = amountOut;
        minBuyAmount = amountIn;
        openBlock = block.number;
        SafeTransferLib.safeApproveWithRetry(tokenOut, RELAYER, amountOut);
        emit FillOpened(tokenOut, tokenIn, amountOut, amountIn);
    }

    /// @notice EIP-1271: accepts a CoW Protocol order for the open fill, in the block in which it was opened.
    /// @dev The signature carries the order and the `ComposableCoW` payload that names the registered conditional
    ///      order. After checking that the digest is the order's, verification is delegated to `ComposableCoW`,
    ///      which checks the registration and calls the order generator's `verify` against the open fill.
    /// @param digest EIP-712 digest of the order, as computed by the settlement contract.
    /// @param signature ABI-encoded `(GPv2OrderLib.Data, IComposableCoW.PayloadStruct)`.
    /// @return The EIP-1271 magic value.
    function isValidSignature(bytes32 digest, bytes calldata signature) external view returns (bytes4) {
        (GPv2OrderLib.Data memory order, IComposableCoW.PayloadStruct memory payload) =
            abi.decode(signature, (GPv2OrderLib.Data, IComposableCoW.PayloadStruct));
        if (GPv2OrderLib.hash(order, DOMAIN_SEPARATOR) != digest) revert OrderRejected(0);
        return COMPOSABLE_COW.isValidSafeSignature(
            address(this), msg.sender, digest, DOMAIN_SEPARATOR, bytes32(0), abi.encode(order), abi.encode(payload)
        );
    }

    /// @inheritdoc ICowFillAgent
    /// @dev The salt is the row index: one conditional order per row, and a new registration for the same row with
    ///      other data has a different hash, so the previous one must be removed by hand.
    function register(uint256 index, bytes32 appDataVaultBuys, bytes32 appDataVaultSells, uint32 bucketSeconds)
        external
        returns (bytes32 singleOrderHash)
    {
        if (msg.sender != IGBLIN(VAULT).owner()) revert Unauthorized();
        IConditionalOrder.ConditionalOrderParams memory params = IConditionalOrder.ConditionalOrderParams({
            handler: ORDER_HANDLER,
            salt: bytes32(index),
            staticInput: abi.encode(GblinAuctionOrder.Data(index, appDataVaultBuys, appDataVaultSells, bucketSeconds))
        });
        singleOrderHash = keccak256(abi.encode(params));
        COMPOSABLE_COW.create(params, true);
        emit AuctionOrderRegistered(index, singleOrderHash);
    }

    /// @inheritdoc ICowFillAgent
    function unregister(bytes32 singleOrderHash) external {
        if (msg.sender != IGBLIN(VAULT).owner()) revert Unauthorized();
        COMPOSABLE_COW.remove(singleOrderHash);
        emit AuctionOrderRemoved(singleOrderHash);
    }

    /// @inheritdoc IFillAgent
    function swapActive() public view returns (bool) {
        if (openBlock != block.number) return false;
        uint256 amount = sellAmount;
        uint256 left = _balance(sellToken);
        if (left >= amount) return false;
        return Math.mulDiv(amount - left, minBuyAmount, amount, Math.Rounding.Ceil) > _balance(buyToken);
    }

    /// @inheritdoc IFillAgent
    function close() external returns (address tokenBought, address tokenSold, uint256 bought, uint256 sold) {
        if (msg.sender != VAULT) revert Unauthorized();
        if (openBlock == 0) return (address(0), address(0), 0, 0);
        if (swapActive()) revert SwapActive();
        tokenBought = buyToken;
        tokenSold = sellToken;
        uint256 amount = sellAmount;
        _clear();
        uint256 left;
        (left, bought) = _returnAll(tokenSold, tokenBought);
        sold = amount > left ? amount - left : 0;
    }

    /// @inheritdoc ICowFillAgent
    /// @dev An order of this agent is only valid in the block its fill was opened, so once that block is past there
    ///      is nothing left to protect, and the tokens go to the vault whoever the caller is. It exists so that a
    ///      fill the vault could not close, for any reason, can never keep this agent or its balances locked.
    function emergencyClose() external {
        if (openBlock == 0 || openBlock == block.number) revert Unauthorized();
        address tokenSold = sellToken;
        address tokenBought = buyToken;
        _clear();
        (uint256 left, uint256 bought) = _returnAll(tokenSold, tokenBought);
        emit FillForceClosed(tokenSold, tokenBought, left, bought);
    }

    /// @inheritdoc ICowFillAgent
    function rescue(address token) external {
        if (openBlock != 0) revert FillOpen();
        SafeTransferLib.safeTransferAll(token, VAULT);
    }

    /// @dev Forgets the open fill.
    function _clear() internal {
        delete sellToken;
        delete buyToken;
        delete sellAmount;
        delete minBuyAmount;
        delete openBlock;
    }

    /// @dev Drops the relayer's allowance and sends both tokens back to the vault, reporting what was still here.
    ///      Nothing here may revert: every call of the vault that moves value closes the fill first, redemptions in
    ///      kind included. A token that refuses the transfer stays here and the vault stops counting it.
    function _returnAll(address tokenSold, address tokenBought) internal returns (uint256 left, uint256 bought) {
        _tryCall(tokenSold, 0x095ea7b3, RELAYER, 0);
        left = _balance(tokenSold);
        if (left != 0 && !_tryCall(tokenSold, 0xa9059cbb, VAULT, left)) emit ReturnFailed(tokenSold, left);
        bought = _balance(tokenBought);
        if (bought != 0 && !_tryCall(tokenBought, 0xa9059cbb, VAULT, bought)) emit ReturnFailed(tokenBought, bought);
    }

    /// @dev Balance of this contract, read with a gas-capped staticcall that copies at most one word: a token that
    ///      reverts, burns gas or returns a huge payload reads as zero and cannot keep the vault from closing the fill.
    function _balance(address token) internal view returns (uint256 b) {
        assembly ("memory-safe") {
            let m := mload(0x40)
            mstore(m, 0x70a0823100000000000000000000000000000000000000000000000000000000)
            mstore(add(m, 0x04), address())
            // Kept apart: Yul evaluates arguments right to left, so returndatasize() must be read after the call.
            let r := staticcall(100000, token, m, 0x24, m, 0x20)
            b := mul(mload(m), and(r, gt(returndatasize(), 31)))
        }
    }

    /// @dev ERC-20 `approve` or `transfer` that reports failure instead of reverting, with at most 200,000 gas and one
    ///      word of returndata read.
    function _tryCall(address token, bytes4 selector, address to, uint256 amount) internal returns (bool ok) {
        assembly ("memory-safe") {
            let m := mload(0x40)
            mstore(m, selector)
            mstore(add(m, 0x04), and(to, 0xffffffffffffffffffffffffffffffffffffffff))
            mstore(add(m, 0x24), amount)
            ok := call(200000, token, 0, m, 0x44, m, 0x20)
            let n := returndatasize()
            ok := and(ok, or(iszero(n), and(gt(n, 31), iszero(iszero(mload(m))))))
        }
    }
}
