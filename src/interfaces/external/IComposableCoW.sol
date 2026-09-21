// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IConditionalOrder} from "./IConditionalOrder.sol";

/// @title IComposableCoW
/// @notice The `ComposableCoW` contract of CoW Protocol, as far as the fill agent uses it: registering single
///         conditional orders and delegating EIP-1271 signature verification to it.
interface IComposableCoW {
    /// @notice What an order's owner passes back to `ComposableCoW` with each signature.
    struct PayloadStruct {
        bytes32[] proof;
        IConditionalOrder.ConditionalOrderParams params;
        bytes offchainInput;
    }

    /// @notice EIP-712 domain separator of the settlement contract, as stored at construction.
    function domainSeparator() external view returns (bytes32);

    /// @notice Verifies a discrete order against a registered conditional order of `safe` and its handler.
    /// @param safe Owner of the conditional order.
    /// @param sender `msg.sender` of the `isValidSignature` call on the owner.
    /// @param _hash EIP-712 digest of the order.
    /// @param domainSeparator Domain separator of the settlement contract.
    /// @param typeHash Unused.
    /// @param encodeData ABI-encoded `GPv2OrderLib.Data`.
    /// @param payload ABI-encoded `PayloadStruct`.
    /// @return The EIP-1271 magic value when the order is accepted; reverts otherwise.
    function isValidSafeSignature(
        address safe,
        address sender,
        bytes32 _hash,
        bytes32 domainSeparator,
        bytes32 typeHash,
        bytes calldata encodeData,
        bytes calldata payload
    ) external view returns (bytes4);

    /// @notice Registers a single conditional order for `msg.sender`.
    /// @param params The conditional order.
    /// @param dispatch True to emit the event the watch-tower indexes.
    function create(IConditionalOrder.ConditionalOrderParams calldata params, bool dispatch) external;

    /// @notice Removes a single conditional order of `msg.sender`.
    /// @param singleOrderHash `keccak256(abi.encode(params))`.
    function remove(bytes32 singleOrderHash) external;

    /// @notice True while `keccak256(abi.encode(params))` is a registered single order of `owner`.
    function singleOrders(address owner, bytes32 singleOrderHash) external view returns (bool);
}
