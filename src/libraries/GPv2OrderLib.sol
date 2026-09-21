// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title GPv2OrderLib
/// @author GBLIN Protocol
/// @notice A CoW Protocol order and its EIP-712 digest, as the settlement contract computes it.
/// @dev Field for field the `GPv2Order.Data` of CoW Protocol, so that a value ABI-encoded here decodes there and
///      back. The marker constants are the keccak-256 of the strings the settlement contract hashes in place of the
///      `kind` and balance fields.
library GPv2OrderLib {
    /// @notice A CoW Protocol order.
    struct Data {
        IERC20 sellToken;
        IERC20 buyToken;
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

    /// @notice keccak-256 of the EIP-712 type string of an order.
    bytes32 internal constant TYPE_HASH = 0xd5a25ba2e97094ad7d83dc28a6572da797d6b3e7fc6663bd93efb789fc17e489;
    /// @notice keccak256("sell"): the order fixes the amount sold.
    bytes32 internal constant KIND_SELL = 0xf3b277728b3fee749481eb3e0b3b48980dbbab78658fc419025cb16eee346775;
    /// @notice keccak256("buy"): the order fixes the amount bought.
    bytes32 internal constant KIND_BUY = 0x6ed88e868af0a1983e3886d5f3e95a2fafbd6c3450bc229e27342283dc429ccc;
    /// @notice keccak256("erc20"): the order moves plain ERC-20 balances.
    bytes32 internal constant BALANCE_ERC20 = 0x5a28e9363bb942b639270062aa6bb295f434bcdfc42c97267bf003f272060dc9;

    /// @notice EIP-712 digest of `order` under `domainSeparator`.
    /// @param order The order.
    /// @param domainSeparator Domain separator of the settlement contract.
    /// @return The digest the settlement contract asks the order's owner to sign.
    function hash(Data memory order, bytes32 domainSeparator) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, keccak256(abi.encode(TYPE_HASH, order))));
    }
}
