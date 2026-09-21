// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IGBLIN} from "../interfaces/IGBLIN.sol";
import {IGBLINLens} from "../interfaces/IGBLINLens.sol";
import {ICowFillAgent} from "../interfaces/ICowFillAgent.sol";
import {IConditionalOrder, IConditionalOrderGenerator} from "../interfaces/external/IConditionalOrder.sol";
import {GPv2OrderLib} from "../libraries/GPv2OrderLib.sol";
import {OracleLib} from "../libraries/OracleLib.sol";

/// @title GBLIN auction order
/// @author GBLIN Protocol
/// @notice A conditional order of the CoW Protocol programmatic order framework that cuts, for one row of the GBLIN
///         basket, the discrete order a solver can settle against the vault's auction: the vault's side, the size of
///         the gap and the auction price, read from the vault through its Lens. The watch-tower of CoW Protocol polls
///         `getTradeableOrder` and posts the result; at settlement `verify` accepts the order only against the fill
///         the order's pre-hook opened in the same block.
/// @dev The generated order is stable within a time bucket: its `validTo` is the end of the bucket and its premium is
///      the auction premium at the start of the bucket, so the watch-tower posts one order per bucket instead of one
///      per block. The premium rises along the bucket, so a fill later in the bucket asks the solvers no more than
///      the order promised. Every read of the vault is guarded: a condition that is not met now reverts with a
///      polling error the watch-tower understands, never with an error that would make it drop the order.
///      The amounts mirror the vault's `bid` arithmetic exactly, conversions and rounding included.
/// @custom:security-contact info@gblin.digital
contract GblinAuctionOrder is IConditionalOrderGenerator {
    /// @notice Data fixed at registration for one basket row.
    /// @param index Basket row.
    /// @param appDataVaultBuys `appData` of the orders in which the vault buys the asset for WETH.
    /// @param appDataVaultSells `appData` of the orders in which the vault sells the asset for WETH.
    /// @param bucketSeconds Length of the time bucket within which the order does not change.
    struct Data {
        uint256 index;
        bytes32 appDataVaultBuys;
        bytes32 appDataVaultSells;
        uint32 bucketSeconds;
    }

    uint256 private constant BPS = 10_000;
    /// @dev Freshness window of the slow feed of a stable asset, as in the vault.
    uint256 private constant STABLE_FEED_MAX_AGE = 26 hours;
    /// @dev Timeout the vault passes to its price reads, as in the vault.
    uint256 private constant PRICE_MAX_AGE = 26 hours;
    /// @dev How long the watch-tower waits before polling again while no fill agent is set on the vault.
    uint256 private constant UNWIRED_RETRY = 1 hours;

    /// @notice The GBLIN vault.
    address public immutable VAULT;
    /// @notice The vault's Lens.
    IGBLINLens public immutable LENS;
    /// @notice WETH, the vault's unit of account.
    address public immutable WETH;

    /// @param vault The GBLIN vault.
    /// @param lens The vault's Lens.
    constructor(address vault, address lens) {
        VAULT = vault;
        LENS = IGBLINLens(lens);
        WETH = IGBLIN(vault).WETH();
    }

    /// @inheritdoc IConditionalOrderGenerator
    /// @dev `sender`, `ctx` and `offchainInput` are unused. The body runs in a call to this contract so that any
    ///      revert of the vault or of a feed is caught here and answered with `PollTryNextBlock`: the watch-tower
    ///      drops a conditional order on any revert it does not recognise, and the vault refusing to price itself
    ///      for a few minutes is not a reason to be dropped.
    function getTradeableOrder(address owner, address, bytes32, bytes calldata staticInput, bytes calldata)
        external
        view
        returns (GPv2OrderLib.Data memory)
    {
        Data memory d = abi.decode(staticInput, (Data));
        if (d.bucketSeconds == 0) revert IConditionalOrder.OrderNotValid("bucket");
        try this.previewOrder(owner, d) returns (GPv2OrderLib.Data memory order) {
            return order;
        } catch (bytes memory reason) {
            _rethrowPollHint(reason);
        }
    }

    /// @notice The order `getTradeableOrder` would return, without the guard; reverts with a polling error when
    ///         there is none.
    /// @dev Public so that `getTradeableOrder` can call it and catch. Reads only.
    /// @param owner The fill agent that owns the conditional order.
    /// @param d Data fixed at registration.
    /// @return order The discrete order.
    function previewOrder(address owner, Data memory d) external view returns (GPv2OrderLib.Data memory order) {
        (address agent, bool fillOpen) = LENS.fill(VAULT);
        if (agent == address(0)) revert IConditionalOrder.PollTryAtEpoch(block.timestamp + UNWIRED_RETRY, "no fill agent");
        if (agent != owner) revert IConditionalOrder.OrderNotValid("owner is not the fill agent");
        if (fillOpen) revert IConditionalOrder.PollTryNextBlock("fill open");

        (bool open, , bool vaultBuysAsset, uint256 gapEth) = LENS.auction(VAULT, d.index);
        if (!open) revert IConditionalOrder.PollTryNextBlock("auction closed");
        if (gapEth == 0) revert IConditionalOrder.PollTryNextBlock("row on target");
        uint256 since = LENS.auctionOpenedAt(VAULT);
        if (since == block.timestamp) revert IConditionalOrder.PollTryNextBlock("auction opened this block");

        (address token, address oracle, bool isStable, , , , , bool abandoned) = LENS.asset(VAULT, d.index);
        if (token == WETH || abandoned) revert IConditionalOrder.OrderNotValid("row cannot be auctioned");

        (uint32 validTo, uint256 factor) = _bucket(since, d.bucketSeconds);
        address wethOracle = LENS.wethOracle(VAULT);
        (, , , , uint256 maxAgeTrade, , ) = LENS.configFees(VAULT);
        if (OracleLib.age(wethOracle) > maxAgeTrade) revert IConditionalOrder.PollTryNextBlock("ETH feed stale");
        if (OracleLib.age(oracle) > (isStable ? STABLE_FEED_MAX_AGE : maxAgeTrade)) {
            revert IConditionalOrder.PollTryNextBlock("asset feed stale");
        }
        uint8 decimals = IERC20Metadata(token).decimals();

        uint256 sellAmount;
        uint256 buyAmount;
        address sellToken;
        address buyToken;
        bytes32 appData;
        if (vaultBuysAsset) {
            // The vault sells WETH for the asset: the gap is bounded by the WETH the holders own, and the WETH paid
            // out carries the premium.
            uint256 held = IERC20(WETH).balanceOf(VAULT);
            uint256 reserved = LENS.reservedAmount(VAULT, WETH);
            uint256 holdersWeth = held > reserved ? held - reserved : 0;
            uint256 affordable = (holdersWeth * BPS) / factor;
            uint256 gap = gapEth > affordable ? affordable : gapEth;
            buyAmount = OracleLib.convert(token, decimals, oracle, gap, WETH, wethOracle, PRICE_MAX_AGE, false);
            sellAmount = (OracleLib.convert(token, decimals, oracle, buyAmount, WETH, wethOracle, PRICE_MAX_AGE, true)
                * factor) / BPS;
            (sellToken, buyToken, appData) = (WETH, token, d.appDataVaultBuys);
        } else {
            // The vault sells the asset for WETH: the WETH it takes in is the gap net of the premium.
            buyAmount = (gapEth * BPS) / factor;
            sellAmount = OracleLib.convert(
                token, decimals, oracle, (buyAmount * factor) / BPS, WETH, wethOracle, PRICE_MAX_AGE, false
            );
            uint256 free = IERC20(token).balanceOf(VAULT);
            uint256 reservedAsset = LENS.reservedAmount(VAULT, token);
            free = free > reservedAsset ? free - reservedAsset : 0;
            if (sellAmount > free) revert IConditionalOrder.PollTryNextBlock("asset balance short");
            (sellToken, buyToken, appData) = (token, WETH, d.appDataVaultSells);
        }
        if (sellAmount == 0 || buyAmount == 0) revert IConditionalOrder.PollTryNextBlock("gap below one unit");

        order = GPv2OrderLib.Data({
            sellToken: IERC20(sellToken),
            buyToken: IERC20(buyToken),
            receiver: owner,
            sellAmount: sellAmount,
            buyAmount: buyAmount,
            validTo: validTo,
            appData: appData,
            feeAmount: 0,
            kind: GPv2OrderLib.KIND_SELL,
            partiallyFillable: true,
            sellTokenBalance: GPv2OrderLib.BALANCE_ERC20,
            buyTokenBalance: GPv2OrderLib.BALANCE_ERC20
        });
    }

    /// @inheritdoc IConditionalOrder
    /// @dev Accepts the order only against the fill the agent holds open in this block, at the fill's price or
    ///      better. Quantity is bounded by the allowance the agent gives the relayer, which is exactly the output the
    ///      vault sent; price by the ratio below, which the settlement rounds in the agent's favour for every trade
    ///      it executes under the order. `kind`, `partiallyFillable` and `validTo` are left unchecked on purpose: an
    ///      order is only accepted in the block its fill was opened, which no `validTo` can widen.
    ///      `code`: 0 not this block, 1 sell token, 2 buy token, 3 fee, 4 receiver, 5 sell balance, 6 buy balance,
    ///      7 zero sell amount, 8 price below the auction price, 9 appData not registered for the row.
    function verify(
        address owner,
        address,
        bytes32,
        bytes32,
        bytes32,
        bytes calldata staticInput,
        bytes calldata,
        GPv2OrderLib.Data calldata order
    ) external view {
        Data memory d = abi.decode(staticInput, (Data));
        ICowFillAgent agent = ICowFillAgent(owner);
        if (agent.openBlock() != block.number) revert ICowFillAgent.OrderRejected(0);
        if (address(order.sellToken) != agent.sellToken()) revert ICowFillAgent.OrderRejected(1);
        if (address(order.buyToken) != agent.buyToken()) revert ICowFillAgent.OrderRejected(2);
        if (order.feeAmount != 0) revert ICowFillAgent.OrderRejected(3);
        if (order.receiver != owner) revert ICowFillAgent.OrderRejected(4);
        if (order.sellTokenBalance != GPv2OrderLib.BALANCE_ERC20) revert ICowFillAgent.OrderRejected(5);
        if (order.buyTokenBalance != GPv2OrderLib.BALANCE_ERC20) revert ICowFillAgent.OrderRejected(6);
        if (order.sellAmount == 0) revert ICowFillAgent.OrderRejected(7);
        // Checked products: an order too large to multiply reverts, which rejects it.
        if (order.buyAmount * agent.sellAmount() < agent.minBuyAmount() * order.sellAmount) {
            revert ICowFillAgent.OrderRejected(8);
        }
        if (order.appData != d.appDataVaultBuys && order.appData != d.appDataVaultSells) {
            revert ICowFillAgent.OrderRejected(9);
        }
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IConditionalOrderGenerator).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    /// @dev End of the current time bucket and the auction factor at its start. A bucket never crosses the point at
    ///      which the vault's premium curve restarts, so the premium can only rise between the order's generation
    ///      and its settlement.
    function _bucket(uint256 since, uint32 bucketSeconds) internal view returns (uint32 validTo, uint256 factor) {
        (, , uint256 auctionStart, uint256 auctionCap, uint256 ramp, , , , ) = LENS.configAuction(VAULT);
        if (ramp == 0) revert IConditionalOrder.PollTryNextBlock("ramp unset");
        uint256 elapsed = block.timestamp - since;
        uint256 bucketStart = since + (elapsed / bucketSeconds) * bucketSeconds;
        uint256 bucketEnd = bucketStart + bucketSeconds;
        uint256 cycle = 2 * ramp;
        uint256 cycleEnd = since + (elapsed / cycle + 1) * cycle;
        uint256 end = bucketEnd < cycleEnd ? bucketEnd : cycleEnd;
        if (end > type(uint32).max) revert IConditionalOrder.OrderNotValid("validTo overflow");
        validTo = uint32(end);

        // The vault's premium at the start of the bucket: from minus `auctionStart` to `auctionCap` along `ramp`
        // seconds, held for another `ramp`, then again from the start.
        uint256 t = (bucketStart - since) % cycle;
        if (t > ramp) t = ramp;
        // Casts are safe: the vault bounds the start and the cap at 300 bps and the ramp at 30 days.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 start = -int256(auctionStart);
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 premium = start + ((int256(auctionCap) - start) * int256(t)) / int256(ramp);
        // forge-lint: disable-next-line(unsafe-typecast)
        factor = uint256(int256(BPS) + premium);
    }

    /// @dev Re-raises a polling error as it is; turns any other revert into `PollTryNextBlock`.
    function _rethrowPollHint(bytes memory reason) internal pure {
        bytes4 selector = reason.length >= 4 ? bytes4(reason) : bytes4(0);
        if (
            selector == IConditionalOrder.OrderNotValid.selector || selector == IConditionalOrder.PollTryNextBlock.selector
                || selector == IConditionalOrder.PollTryAtBlock.selector
                || selector == IConditionalOrder.PollTryAtEpoch.selector || selector == IConditionalOrder.PollNever.selector
        ) {
            assembly ("memory-safe") {
                revert(add(reason, 32), mload(reason))
            }
        }
        revert IConditionalOrder.PollTryNextBlock("vault unavailable");
    }
}
