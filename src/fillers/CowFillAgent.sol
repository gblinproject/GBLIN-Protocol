// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IGBLIN} from "../interfaces/IGBLIN.sol";
import {IAuctionCallback} from "../interfaces/IAuctionCallback.sol";
import {IFillAgent} from "../interfaces/IFillAgent.sol";
import {IGPv2Settlement} from "../interfaces/external/IGPv2Settlement.sol";

/// @title CoW Protocol fill agent for GBLIN auctions
/// @author GBLIN Protocol
/// @notice Bids in the vault's auction without paying at once, and lets CoW Protocol solvers settle the fill in the
///         same block through an EIP-1271 order at the auction price or better. When the vault closes the fill, every
///         unit of the two tokens goes back to it, including any surplus the solvers delivered.
/// @dev One fill, inside one CoW settlement: the order's pre-hook calls `openFill`, which bids with no input limit; the
///      vault sends its output here, calls `onAuctionFill` and, because the caller is its fill agent, leaves the fill
///      open instead of pulling the input. The settlement then verifies the order through `isValidSignature`, pulls the
///      sold token through the vault relayer and delivers the bought token here; the post-hook calls the vault's
///      `refreshWeights`, which calls `close`. Any later call of the vault that moves value closes the fill as well.
///      The pattern follows the trusted fillers of Reserve Protocol (MIT). The agent has no owner and keeps no balance
///      between fills.
/// @custom:security-contact info@gblin.digital
contract CowFillAgent is IFillAgent, IAuctionCallback {
    /// @notice The caller is not the vault, or the order is used outside the block in which the fill was opened.
    error Unauthorized();
    /// @notice A fill is open.
    error FillOpen();
    /// @notice A swap has taken part of the sold token without delivering the bought one.
    error SwapActive();
    /// @notice The order does not match the open fill. `code`: 0 digest, 1 sell token, 2 buy token, 3 fee, 4 receiver,
    ///         5 sell balance, 6 buy balance, 7 zero sell amount, 8 price below the auction price.
    error OrderRejected(uint256 code);

    /// @notice The vault opened a fill of `sellAmount` of `sellToken` for at least `minBuyAmount` of `buyToken`.
    event FillOpened(address indexed sellToken, address indexed buyToken, uint256 sellAmount, uint256 minBuyAmount);
    /// @notice Closing could not send `amount` of `token` back to the vault; it stays here until `rescue` succeeds.
    event ReturnFailed(address indexed token, uint256 amount);
    /// @notice A fill left open in an earlier block was cleared with `emergencyClose`.
    event FillForceClosed(address indexed sellToken, address indexed buyToken, uint256 sellReturned, uint256 bought);

    /// @notice A CoW Protocol order, field for field in the order the settlement contract hashes it.
    struct Order {
        address sellToken;
        address buyToken;
        address receiver;
        uint256 sellAmount;
        uint256 buyAmount;
        uint32 validTo;
        bytes32 appData;
        uint256 feeAmount;
        bytes32 kind;
        bool partiallyFillable;
        bytes32 sellTokenBalance;
        bytes32 buyTokenBalance;
    }

    /// @dev keccak256 of the EIP-712 type string of a CoW Protocol order.
    bytes32 private constant ORDER_TYPE_HASH = 0xd5a25ba2e97094ad7d83dc28a6572da797d6b3e7fc6663bd93efb789fc17e489;
    /// @dev keccak256("erc20"): the order moves plain ERC-20 balances.
    bytes32 private constant BALANCE_ERC20 = 0x5a28e9363bb942b639270062aa6bb295f434bcdfc42c97267bf003f272060dc9;

    /// @notice The vault this agent serves.
    address public immutable VAULT;
    /// @notice CoW Protocol vault relayer, the only spender of the sold token.
    address public immutable RELAYER;
    /// @notice EIP-712 domain separator of the CoW Protocol settlement contract.
    bytes32 public immutable DOMAIN_SEPARATOR;

    /// @notice Token the open fill sells.
    address public sellToken;
    /// @notice Token the open fill buys.
    address public buyToken;
    /// @notice Amount of `sellToken` the vault sent for the open fill.
    uint256 public sellAmount;
    /// @notice Least amount of `buyToken` for the whole `sellAmount`; a partial sale needs its pro rata part, rounded
    ///         up.
    uint256 public minBuyAmount;
    /// @notice Block in which the open fill was opened; zero when no fill is open.
    uint256 public openBlock;

    /// @param vault The GBLIN vault.
    /// @param settlement The CoW Protocol settlement contract.
    constructor(address vault, address settlement) {
        VAULT = vault;
        RELAYER = IGPv2Settlement(settlement).vaultRelayer();
        DOMAIN_SEPARATOR = IGPv2Settlement(settlement).domainSeparator();
    }

    /// @notice Opens a fill of the auction of the vault's `basket[index]`: bids with no input limit and keeps the
    ///         output for CoW Protocol orders in this block. Anyone can call; meant as the pre-hook of the agent's
    ///         order.
    /// @param index Basket row.
    /// @param vaultBuysAsset As in the vault's `bid`.
    /// @return amountIn Least amount of the input the solvers must deliver for the whole output, pro rata if partly
    ///                  sold.
    /// @return amountOut Output received from the vault.
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
    /// @dev The price check multiplies exactly, without rounding: `buyAmount / sellAmount` of the order must be at
    ///      least `minBuyAmount / sellAmount` of the fill. The settlement contract rounds each executed buy amount up,
    ///      so every trade it executes under this order also meets the fill's price.
    ///      `kind`, `partiallyFillable` and `validTo` are left unchecked on purpose. Quantity is bounded by the
    ///      allowance this contract gives the relayer, which is exactly the output the vault sent, so an order larger
    ///      than the fill cannot take more. Price is bounded by the ratio below for either kind: the settlement
    ///      rounds the amount this contract buys up and the amount it sells down. And an order is only accepted in
    ///      the block its fill was opened, which no `validTo` can widen.
    /// @param digest EIP-712 digest of the order, as computed by the settlement contract.
    /// @param signature The order, ABI-encoded.
    /// @return The EIP-1271 magic value.
    function isValidSignature(bytes32 digest, bytes calldata signature) external view returns (bytes4) {
        if (openBlock != block.number) revert Unauthorized();
        Order memory o = abi.decode(signature, (Order));
        bytes32 structHash = keccak256(abi.encode(ORDER_TYPE_HASH, o));
        if (digest != keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash))) revert OrderRejected(0);
        if (o.sellToken != sellToken) revert OrderRejected(1);
        if (o.buyToken != buyToken) revert OrderRejected(2);
        if (o.feeAmount != 0) revert OrderRejected(3);
        if (o.receiver != address(this)) revert OrderRejected(4);
        if (o.sellTokenBalance != BALANCE_ERC20) revert OrderRejected(5);
        if (o.buyTokenBalance != BALANCE_ERC20) revert OrderRejected(6);
        if (o.sellAmount == 0) revert OrderRejected(7);
        // Checked products: an order too large to multiply reverts, which rejects it.
        if (o.buyAmount * sellAmount < minBuyAmount * o.sellAmount) revert OrderRejected(8);
        return this.isValidSignature.selector;
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

    /// @notice Clears a fill left open in an earlier block and sends every unit of its two tokens back to the vault.
    /// @dev Anyone may call it and it cannot fail. An order of this agent is only valid in the block its fill was
    ///      opened, so once that block is past there is nothing left to protect, and the tokens go to the vault
    ///      whoever the caller is. It exists so that a fill the vault could not close, for any reason, can never keep
    ///      this agent or its balances locked.
    function emergencyClose() external {
        if (openBlock == 0 || openBlock == block.number) revert Unauthorized();
        address tokenSold = sellToken;
        address tokenBought = buyToken;
        _clear();
        (uint256 left, uint256 bought) = _returnAll(tokenSold, tokenBought);
        emit FillForceClosed(tokenSold, tokenBought, left, bought);
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

    /// @notice Sends the whole balance of `token` to the vault while no fill is open.
    /// @param token Token to send.
    function rescue(address token) external {
        if (openBlock != 0) revert FillOpen();
        SafeTransferLib.safeTransferAll(token, VAULT);
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
