// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {GPv2OrderLib} from "../../libraries/GPv2OrderLib.sol";

/// @title IConditionalOrder
/// @notice A conditional order of the CoW Protocol programmatic order framework, as its `ComposableCoW` contract
///         calls it. Every error, struct and function keeps the signature of the framework, so the selectors match.
interface IConditionalOrder {
    /// @notice The parameters of the conditional order describe no valid order. The watch-tower stops polling it.
    error OrderNotValid(string);
    /// @notice No order right now; the watch-tower polls again on the next block.
    error PollTryNextBlock(string reason);
    /// @notice No order right now; the watch-tower polls again at `blockNumber`.
    error PollTryAtBlock(uint256 blockNumber, string reason);
    /// @notice No order right now; the watch-tower polls again at `timestamp`.
    error PollTryAtEpoch(uint256 timestamp, string reason);
    /// @notice No order ever again; the watch-tower stops polling it.
    error PollNever(string reason);

    /// @notice What identifies a conditional order of an owner: `keccak256(abi.encode(params))` must be unique.
    struct ConditionalOrderParams {
        IConditionalOrder handler;
        bytes32 salt;
        bytes staticInput;
    }

    /// @notice Accepts or rejects a discrete order cut from the conditional order. Called by `ComposableCoW` during
    ///         signature verification; must revert to reject.
    /// @param owner Owner of the conditional order.
    /// @param sender `msg.sender` of the `isValidSignature` call on the owner.
    /// @param _hash EIP-712 digest of `order`.
    /// @param domainSeparator Domain separator of the settlement contract.
    /// @param ctx `keccak256(abi.encode(params))` for a single order.
    /// @param staticInput Data fixed at registration for every discrete order.
    /// @param offchainInput Data supplied with this discrete order; empty when unused.
    /// @param order The discrete order the settlement is executing.
    function verify(
        address owner,
        address sender,
        bytes32 _hash,
        bytes32 domainSeparator,
        bytes32 ctx,
        bytes calldata staticInput,
        bytes calldata offchainInput,
        GPv2OrderLib.Data calldata order
    ) external view;
}

/// @title IConditionalOrderGenerator
/// @notice A conditional order that also generates its discrete orders, for the watch-tower to post.
interface IConditionalOrderGenerator is IConditionalOrder, IERC165 {
    /// @notice A conditional order was registered with `ComposableCoW`.
    /// @param owner Owner of the conditional order.
    /// @param params Its parameters.
    event ConditionalOrderCreated(address indexed owner, IConditionalOrder.ConditionalOrderParams params);

    /// @notice The discrete order to post right now, or a revert with one of the polling errors.
    /// @param owner Owner of the conditional order.
    /// @param sender `msg.sender` of the enclosing call.
    /// @param ctx `keccak256(abi.encode(params))` for a single order.
    /// @param staticInput Data fixed at registration.
    /// @param offchainInput Data supplied by the caller; empty when unused.
    /// @return The order to post.
    function getTradeableOrder(
        address owner,
        address sender,
        bytes32 ctx,
        bytes calldata staticInput,
        bytes calldata offchainInput
    ) external view returns (GPv2OrderLib.Data memory);
}
