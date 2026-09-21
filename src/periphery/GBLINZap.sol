// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IGBLIN} from "../interfaces/IGBLIN.sol";
import {IGBLINLens} from "../interfaces/IGBLINLens.sol";
import {ISwapAdapter} from "../interfaces/ISwapAdapter.sol";
import {IWETH} from "../interfaces/external/IWETH.sol";

/// @title GBLIN Zap
/// @author GBLIN Protocol
/// @notice The vault never swaps. This contract does it for the holder: it mints GBLIN with any token, and it redeems
///         GBLIN to ETH by redeeming in kind on the vault and selling every leg through a swap adapter.
/// @dev Periphery without owner, settings or balance between calls. The adapter is not trusted: every allowance is
///      exact and reset to zero, and every output is measured on this contract's own balance. A price the adapter
///      delivers badly can only hurt the caller of this contract, never the vault: the vault's side of both paths is a
///      mint at NAV or a redemption in kind.
/// @custom:security-contact info@gblin.digital
contract GBLINZap is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 private constant BPS = 10_000;
    /// @dev Upper bound of `maxSlippageBps`.
    uint256 private constant HARD_MAX_SLIPPAGE_BPS = 300;

    /// @notice A zero amount or minimum, a token that is WETH or the vault itself, routing data that does not match the
    ///         basket, or a slippage bound outside its limits.
    error InvalidAmount();
    /// @notice The zero address, an address without code, or a receiver that is this contract or the vault.
    error InvalidAddress();
    /// @notice The token did not move the exact amount requested.
    error TokenNotConformant();
    /// @notice The output is below the caller's minimum or below the NAV floor.
    error SlippageExceeded();
    /// @notice The vault cannot price itself and the caller set no minimum.
    error PriceUnavailable();
    /// @notice The vault credited a leg to this contract instead of delivering it.
    error LegNotDelivered(address token);
    /// @notice The receiver refused the ETH.
    error EthRefused();

    /// @notice `amountIn` of `tokenIn` was swapped into `wethIn` WETH, which minted `shares` to `receiver`.
    event MintedWithToken(
        address indexed receiver, address indexed tokenIn, uint256 amountIn, uint256 wethIn, uint256 shares
    );
    /// @notice `shares` of `holder` were redeemed in kind and their legs sold into `ethOut` wei of ETH for `receiver`.
    event RedeemedForEth(address indexed holder, address indexed receiver, uint256 shares, uint256 ethOut);

    /// @notice The GBLIN vault.
    address public immutable vault;
    /// @notice Wrapped ether.
    address public immutable WETH;
    /// @notice Swap adapter used for every conversion.
    ISwapAdapter public immutable adapter;
    /// @notice Lens that reads the vault's basket and credits.
    IGBLINLens public immutable lens;
    /// @notice Largest shortfall of an ETH redemption below the NAV value of the shares, in bps.
    uint256 public immutable maxSlippageBps;

    /// @param _vault GBLIN vault.
    /// @param _weth Wrapped ether.
    /// @param _adapter Swap adapter.
    /// @param _lens GBLIN Lens.
    /// @param _maxSlippageBps Largest shortfall below NAV accepted by `sellGBLINForEth`; 1 to 300.
    constructor(address _vault, address _weth, address _adapter, address _lens, uint256 _maxSlippageBps) {
        if (_vault == address(0) || _weth == address(0) || _adapter == address(0) || _lens == address(0)) {
            revert InvalidAddress();
        }
        if (_vault.code.length == 0 || _weth.code.length == 0 || _adapter.code.length == 0 || _lens.code.length == 0) {
            revert InvalidAddress();
        }
        if (_maxSlippageBps == 0 || _maxSlippageBps > HARD_MAX_SLIPPAGE_BPS) revert InvalidAmount();
        vault = _vault;
        WETH = _weth;
        adapter = ISwapAdapter(_adapter);
        lens = IGBLINLens(_lens);
        maxSlippageBps = _maxSlippageBps;
    }

    /// @notice Accepts ETH from the vault's redemptions and from unwrapping WETH.
    receive() external payable {}

    /// @notice Swaps `amountIn` of `tokenIn` into at least `minWethOut` WETH and mints at least `minOut` shares to
    ///         `receiver`.
    /// @dev Any input the adapter leaves is returned to the caller. The swap's price risk stays with `minWethOut`.
    /// @param tokenIn Token to spend; not WETH and not the vault.
    /// @param amountIn Amount of `tokenIn` pulled from the caller.
    /// @param minWethOut Minimum WETH from the swap; positive.
    /// @param minOut Minimum shares minted.
    /// @param venueData Adapter routing data from `tokenIn` to WETH.
    /// @param receiver Account that receives the shares.
    /// @return out Shares minted to `receiver`.
    function buyGBLINWithToken(
        address tokenIn,
        uint256 amountIn,
        uint256 minWethOut,
        uint256 minOut,
        bytes calldata venueData,
        address receiver
    ) external nonReentrant returns (uint256 out) {
        if (amountIn == 0 || minWethOut == 0) revert InvalidAmount();
        if (tokenIn == WETH || tokenIn == vault) revert InvalidAmount();
        // Neither this contract nor the vault may receive the shares: the vault writes the redemption cooldown of a
        // receiver that is the minter itself, and this contract is the minter here. A caller who named it as receiver
        // would put every redemption for ETH on cooldown, and shares minted to either contract could never be redeemed.
        if (receiver == address(0) || receiver == address(this) || receiver == vault) revert InvalidAddress();

        uint256 before = IERC20(tokenIn).balanceOf(address(this));
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        if (IERC20(tokenIn).balanceOf(address(this)) - before != amountIn) revert TokenNotConformant();

        uint256 wethBefore = IERC20(WETH).balanceOf(address(this));
        IERC20(tokenIn).forceApprove(address(adapter), amountIn);
        adapter.swap(tokenIn, WETH, amountIn, minWethOut, venueData);
        IERC20(tokenIn).forceApprove(address(adapter), 0);
        uint256 got = IERC20(WETH).balanceOf(address(this)) - wethBefore;
        if (got < minWethOut) revert SlippageExceeded();

        uint256 leftover = IERC20(tokenIn).balanceOf(address(this)) - before;
        if (leftover > 0) IERC20(tokenIn).safeTransfer(msg.sender, leftover);

        uint256 balanceBefore = IERC20(vault).balanceOf(receiver);
        IERC20(WETH).forceApprove(vault, got);
        IGBLIN(vault).buyGBLINWithWeth(got, minOut, receiver);
        out = IERC20(vault).balanceOf(receiver) - balanceBefore;
        emit MintedWithToken(receiver, tokenIn, amountIn, got, out);
    }

    /// @notice Redeems `shares` of the caller in kind and sells every leg for ETH, sent to `receiver`.
    /// @dev All or nothing: a leg the adapter cannot sell, or that the vault credits instead of delivering, reverts the
    ///      whole call and the caller keeps its shares; redeeming in kind on the vault stays open. The ETH must reach
    ///      `minEthOut` and, while the vault can price itself, the NAV value of the shares less `maxSlippageBps`; while
    ///      it cannot, a positive `minEthOut` is required. Units of a leg the adapter leaves unsold are sent to
    ///      `receiver`. A leg whose token does not answer `balanceOf` is skipped, as the vault skips it.
    /// @param shares Shares pulled from the caller, who must have approved this contract.
    /// @param minEthOut Minimum ETH accepted.
    /// @param venueData Adapter routing data per basket row, index for index; ignored for WETH and abandoned rows.
    /// @param receiver Account that receives the ETH.
    /// @return ethOut ETH sent to `receiver`.
    function sellGBLINForEth(uint256 shares, uint256 minEthOut, bytes[] calldata venueData, address receiver)
        external
        nonReentrant
        returns (uint256 ethOut)
    {
        if (shares == 0) revert InvalidAmount();
        if (receiver == address(0)) revert InvalidAddress();
        uint256 n = lens.basketLength(vault);
        if (venueData.length != n) revert InvalidAmount();

        uint256 floor = minEthOut;
        if (IGBLIN(vault).isNavReliable()) {
            uint256 atNav = (shares * IGBLIN(vault).navPerShare(0)) / 1 ether;
            uint256 navFloor = atNav - (atNav * maxSlippageBps) / BPS;
            if (navFloor > floor) floor = navFloor;
        } else if (minEthOut == 0) {
            revert PriceUnavailable();
        }

        uint256 sharesBefore = IERC20(vault).balanceOf(address(this));
        IERC20(vault).safeTransferFrom(msg.sender, address(this), shares);
        if (IERC20(vault).balanceOf(address(this)) - sharesBefore != shares) revert TokenNotConformant();

        address[] memory tokens = new address[](n);
        uint256[] memory held = new uint256[](n);
        for (uint256 i = 0; i < n; ++i) {
            (address t,,,,,,, bool abandoned) = lens.asset(vault, i);
            if (abandoned) continue;
            (uint256 b, bool answered) = _balanceOf(t);
            if (!answered) continue;
            tokens[i] = t;
            held[i] = b;
        }
        uint256 wethHeld = IERC20(WETH).balanceOf(address(this));
        uint256 ethBefore = address(this).balance;

        IGBLIN(vault).sellGBLIN(shares);

        for (uint256 i = 0; i < n; ++i) {
            address t = tokens[i];
            if (t == address(0)) continue;
            if (lens.pendingWithdrawal(vault, address(this), t) != 0) revert LegNotDelivered(t);
            if (t == WETH) continue;
            uint256 got = IERC20(t).balanceOf(address(this)) - held[i];
            if (got == 0) continue;
            IERC20(t).forceApprove(address(adapter), got);
            adapter.swap(t, WETH, got, 1, venueData[i]);
            IERC20(t).forceApprove(address(adapter), 0);
            uint256 left = IERC20(t).balanceOf(address(this)) - held[i];
            if (left > 0) IERC20(t).safeTransfer(receiver, left);
        }

        uint256 wethGot = IERC20(WETH).balanceOf(address(this)) - wethHeld;
        if (wethGot > 0) IWETH(WETH).withdraw(wethGot);
        ethOut = address(this).balance - ethBefore;
        if (ethOut < floor) revert SlippageExceeded();

        (bool ok,) = payable(receiver).call{value: ethOut}("");
        if (!ok) revert EthRefused();
        emit RedeemedForEth(msg.sender, receiver, shares, ethOut);
    }

    /// @dev This contract's balance of `t`, read with a gas-capped staticcall that copies at most one word; `answered`
    ///      is false for a token that reverts or returns less than a word.
    function _balanceOf(address t) internal view returns (uint256 b, bool answered) {
        assembly ("memory-safe") {
            let m := mload(0x40)
            mstore(m, 0x70a0823100000000000000000000000000000000000000000000000000000000)
            mstore(add(m, 0x04), address())
            // Kept apart: Yul evaluates arguments right to left, so returndatasize() is read after the call.
            let r := staticcall(100000, t, m, 0x24, m, 0x20)
            answered := and(r, gt(returndatasize(), 31))
            b := mul(mload(m), answered)
        }
    }
}
