// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IGBLIN} from "../interfaces/IGBLIN.sol";
import {IGBLINLens} from "../interfaces/IGBLINLens.sol";
import {AggregatorV3Interface} from "../interfaces/external/AggregatorV3Interface.sol";

/// @title GBLIN Lens
/// @author GBLIN Protocol
/// @notice Read-only helper for the GBLIN vault: configuration, accounting, quotes and auction state.
/// @dev Stateless and without privileges; every function takes the vault as its first argument. Values are read from
///      the vault's storage with `extsload` and from its public views, so this contract follows the vault's storage
///      layout, which is fixed at deployment.
/// @custom:security-contact info@gblin.digital
contract GBLINLens is IGBLINLens {
    uint256 private constant BPS = 10_000;
    uint256 private constant VIRTUAL_SHARES = 1e6;
    uint256 private constant VIRTUAL_ASSETS = 1;
    /// @dev OpenZeppelin ReentrancyGuard slot (ERC-7201); it reads 2 while the vault is executing a locked call.
    bytes32 private constant REENTRANCY_GUARD_SLOT = 0x9b779b17422d0df92223018b32b4d1fa46e071723d6817e2486d003becc55f00;

    uint256 private constant S_INKIND_FEE = 0;
    uint256 private constant S_INKIND_TAX = 1;
    uint256 private constant S_WETH_ORACLE = 2;
    uint256 private constant S_SEQUENCER = 3;
    uint256 private constant S_FEE_RECIPIENT = 5;
    uint256 private constant S_PROTOCOL_FEE = 6;
    uint256 private constant S_STABILITY_FEE = 7;
    uint256 private constant S_MIN_DEPOSIT = 8;
    uint256 private constant S_ORACLE_TIMEOUT = 9;
    uint256 private constant S_ORACLE_AGE_TRADE = 10;
    /// @dev First of the ten crash shield settings, stored in `configShield` order.
    uint256 private constant S_SHIELD_FIRST = 11;
    uint256 private constant S_DRIFT_BAND = 21;
    uint256 private constant S_DRIFT_CLOSE = 22;
    uint256 private constant S_AUCTION_START = 23;
    uint256 private constant S_AUCTION_CAP = 24;
    uint256 private constant S_AUCTION_RAMP = 25;
    uint256 private constant S_VOL_INTERVAL = 26;
    uint256 private constant S_BASKET = 27;
    uint256 private constant S_DRIFT_SINCE = 32;
    uint256 private constant S_LAST_VOL_REFRESH = 33;
    uint256 private constant S_PENDING_WITHDRAWAL = 34;
    uint256 private constant S_RESERVED = 35;
    uint256 private constant S_ABANDONED = 36;
    uint256 private constant S_PENDING_OWNER = 37;
    uint256 private constant S_SELL_COOLDOWN = 38;
    uint256 private constant S_LAST_DEPOSIT = 39;
    uint256 private constant S_MAX_BASKET = 40;
    uint256 private constant S_LISTING_DELAY = 41;
    uint256 private constant S_MANAGEMENT_FEE = 43;
    uint256 private constant S_LAST_MANAGEMENT_FEE_ACCRUAL = 44;
    /// @dev Fill agent in the low 160 bits, open flag in the next byte, then the opening block (8 bytes), the basket
    ///      row of the open fill (1 byte) and its direction (1 byte).
    uint256 private constant S_FILL = 45;
    /// @dev Storage slots per basket row.
    uint256 private constant ROW_SLOTS = 12;

    /*//////////////////////////////////////////////////////////////
                               ACCOUNTING
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGBLINLens
    function basketLength(address vault) external view returns (uint256) {
        return _s(vault, S_BASKET);
    }

    /// @inheritdoc IGBLINLens
    function auctionOpenedAt(address vault) external view returns (uint256) {
        return _s(vault, S_DRIFT_SINCE);
    }

    /// @inheritdoc IGBLINLens
    function lastVolRefresh(address vault) external view returns (uint256) {
        return _s(vault, S_LAST_VOL_REFRESH);
    }

    /// @inheritdoc IGBLINLens
    function pendingWithdrawal(address vault, address holder, address token) external view returns (uint256) {
        return _m(vault, keccak256(abi.encode(token, keccak256(abi.encode(holder, S_PENDING_WITHDRAWAL)))));
    }

    /// @inheritdoc IGBLINLens
    function reservedAmount(address vault, address token) external view returns (uint256) {
        return _m(vault, keccak256(abi.encode(token, S_RESERVED)));
    }

    /// @inheritdoc IGBLINLens
    function abandonedMask(address vault) external view returns (uint256) {
        return _s(vault, S_ABANDONED);
    }

    /// @inheritdoc IGBLINLens
    function lastDepositTime(address vault, address holder) external view returns (uint256) {
        return _m(vault, keccak256(abi.encode(holder, S_LAST_DEPOSIT)));
    }

    /// @inheritdoc IGBLINLens
    function reentrancyLocked(address vault) external view returns (bool) {
        return _m(vault, REENTRANCY_GUARD_SLOT) == 2;
    }

    /*//////////////////////////////////////////////////////////////
                               ADDRESSES
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGBLINLens
    function wethOracle(address vault) external view returns (address) {
        return _a(_s(vault, S_WETH_ORACLE));
    }

    /// @inheritdoc IGBLINLens
    function sequencerFeed(address vault) external view returns (address) {
        return _a(_s(vault, S_SEQUENCER));
    }

    /// @inheritdoc IGBLINLens
    function feeRecipient(address vault) external view returns (address) {
        return _a(_s(vault, S_FEE_RECIPIENT));
    }

    /// @inheritdoc IGBLINLens
    function pendingOwner(address vault) external view returns (address) {
        return _a(_s(vault, S_PENDING_OWNER));
    }

    /*//////////////////////////////////////////////////////////////
                                 QUOTES
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGBLINLens
    function quoteBuy(address vault, uint256 ethValue)
        external
        view
        returns (uint256 out, uint256 protocolFee, uint256 stabilityFee)
    {
        if (!IGBLIN(vault).isNavReliable()) revert IGBLIN.PriceUnavailable();
        protocolFee = (ethValue * _s(vault, S_PROTOCOL_FEE)) / BPS;
        stabilityFee = (ethValue * _s(vault, S_STABILITY_FEE)) / BPS;
        out = ((ethValue - protocolFee - stabilityFee) * (_supplyAfterAccrual(vault) + VIRTUAL_SHARES))
            / (_assets(vault) + VIRTUAL_ASSETS);
    }

    /// @inheritdoc IGBLINLens
    function quoteSell(address vault, uint256 gblinAmount) external view returns (uint256) {
        if (!IGBLIN(vault).isNavReliable()) revert IGBLIN.PriceUnavailable();
        return (gblinAmount * (_assets(vault) + VIRTUAL_ASSETS)) / (_supplyAfterAccrual(vault) + VIRTUAL_SHARES);
    }

    /*//////////////////////////////////////////////////////////////
                             CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGBLINLens
    function configFees(address vault)
        external
        view
        returns (
            uint256 protocolFee,
            uint256 stabilityFee,
            uint256 minDeposit,
            uint256 oracleAge,
            uint256 oracleAgeTrade,
            uint256 sellCooldown,
            uint256 basketCap
        )
    {
        uint256[] memory q = new uint256[](7);
        (q[0], q[1], q[2], q[3], q[4], q[5], q[6]) =
        (
            S_PROTOCOL_FEE,
            S_STABILITY_FEE,
            S_MIN_DEPOSIT,
            S_ORACLE_TIMEOUT,
            S_ORACLE_AGE_TRADE,
            S_SELL_COOLDOWN,
            S_MAX_BASKET
        );
        uint256[] memory r = _readMany(vault, q);
        return (r[0], r[1], r[2], r[3], r[4], r[5], r[6]);
    }

    /// @inheritdoc IGBLINLens
    function configShield(address vault)
        external
        view
        returns (
            uint256 baseCrashThreshold,
            uint256 volMultiplier,
            uint256 recoveryBand,
            uint256 slashMultiplier,
            uint256 peakDecayPerDay,
            uint256 slowPeakDecayPerDay,
            uint256 fullSlashDrawdown,
            uint256 minCrash,
            uint256 maxCrash,
            uint256 pegBand
        )
    {
        uint256[] memory q = new uint256[](10);
        for (uint256 i = 0; i < 10; ++i) {
            q[i] = S_SHIELD_FIRST + i;
        }
        uint256[] memory r = _readMany(vault, q);
        return (r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9]);
    }

    /// @inheritdoc IGBLINLens
    function configAuction(address vault)
        external
        view
        returns (
            uint256 driftBand,
            uint256 driftClose,
            uint256 auctionStart,
            uint256 auctionCap,
            uint256 auctionRamp,
            uint256 volUpdateInterval,
            uint256 listingDelay,
            uint256 inKindFee,
            uint256 inKindTax
        )
    {
        uint256[] memory q = new uint256[](9);
        (q[0], q[1], q[2], q[3], q[4], q[5], q[6], q[7], q[8]) =
        (
            S_DRIFT_BAND,
            S_DRIFT_CLOSE,
            S_AUCTION_START,
            S_AUCTION_CAP,
            S_AUCTION_RAMP,
            S_VOL_INTERVAL,
            S_LISTING_DELAY,
            S_INKIND_FEE,
            S_INKIND_TAX
        );
        uint256[] memory r = _readMany(vault, q);
        return (r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8]);
    }

    /// @inheritdoc IGBLINLens
    function managementFeeBps(address vault) external view returns (uint256) {
        return _s(vault, S_MANAGEMENT_FEE);
    }

    /// @inheritdoc IGBLINLens
    function lastManagementFeeAccrual(address vault) external view returns (uint256) {
        return _s(vault, S_LAST_MANAGEMENT_FEE_ACCRUAL);
    }

    /*//////////////////////////////////////////////////////////////
                             BASKET AND AUCTION
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGBLINLens
    function asset(address vault, uint256 i)
        external
        view
        returns (
            address token,
            address oracle,
            bool isStable,
            bool delisted,
            uint256 baseWeight,
            uint256 dynamicWeight,
            bool shielded,
            bool abandoned
        )
    {
        if (i >= _s(vault, S_BASKET)) revert IGBLIN.InvalidIndex();
        uint256 base = _rowBase(i);
        uint256[] memory q = new uint256[](6);
        (q[0], q[1], q[2], q[3], q[4], q[5]) = (base, base + 1, base + 2, base + 3, base + 10, S_ABANDONED);
        uint256[] memory r = _readMany(vault, q);
        token = _a(r[0]);
        oracle = _a(r[1]);
        isStable = ((r[1] >> 160) & 0xFF) != 0;
        delisted = ((r[1] >> 168) & 0xFF) != 0;
        baseWeight = r[2];
        dynamicWeight = r[3];
        shielded = r[4] != 0;
        abandoned = ((r[5] >> i) & 1) == 1;
    }

    /// @inheritdoc IGBLINLens
    function auction(address vault, uint256 i)
        external
        view
        returns (bool open, int256 premiumBps, bool vaultBuysAsset, uint256 gapEth)
    {
        open = _s(vault, S_DRIFT_SINCE) != 0;
        premiumBps = IGBLIN(vault).auctionPremiumBps();
        if (i >= _s(vault, S_BASKET)) return (open, premiumBps, false, 0);

        uint256 base = _rowBase(i);
        uint256[] memory q = new uint256[](4);
        (q[0], q[1], q[2], q[3]) = (base, base + 1, base + 3, S_ABANDONED);
        uint256[] memory r = _readMany(vault, q);
        address token = _a(r[0]);
        if (token == IGBLIN(vault).WETH() || ((r[3] >> i) & 1) == 1) return (open, premiumBps, false, 0);

        uint256 target = (IGBLIN(vault).totalEthValue(0) * r[2]) / BPS;
        uint256 bal = _balanceOf(token, vault);
        uint256 fillSlot = _s(vault, S_FILL);
        // The agent's balance counts only for the two tokens of the open fill, as in the vault; WETH returned above.
        if ((fillSlot >> 160) & 0xff != 0 && ((fillSlot >> 232) & 0xff) == i) bal += _balanceOf(token, _a(fillSlot));
        uint256 reserved = _m(vault, keccak256(abi.encode(token, S_RESERVED)));
        uint256 free = bal > reserved ? bal - reserved : 0;
        uint256 cur = _ethValue(uint8(r[0] >> 160), _a(r[1]), free, _a(_s(vault, S_WETH_ORACLE)));
        if (cur < target) return (open, premiumBps, true, target - cur);
        return (open, premiumBps, false, cur - target);
    }

    /// @inheritdoc IGBLINLens
    function fill(address vault) external view returns (address agent, bool open) {
        uint256 x = _s(vault, S_FILL);
        return (_a(x), (x >> 160) & 0xff != 0);
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    /// @dev Total supply after the management fee that the next mint or redemption accrues.
    function _supplyAfterAccrual(address vault) internal view returns (uint256 s) {
        s = IERC20Metadata(vault).totalSupply();
        uint256 t = _s(vault, S_LAST_MANAGEMENT_FEE_ACCRUAL);
        if (t == 0 || block.timestamp <= t) return s;
        s += (s * _s(vault, S_MANAGEMENT_FEE) * (block.timestamp - t)) / (BPS * 365 days);
    }

    /// @dev NAV in wei of ETH plus the stray ETH that the vault wraps before pricing.
    function _assets(address vault) internal view returns (uint256) {
        return IGBLIN(vault).totalEthValue(0) + vault.balance;
    }

    function _s(address vault, uint256 slot) internal view returns (uint256) {
        return _m(vault, bytes32(slot));
    }

    function _m(address vault, bytes32 slot) internal view returns (uint256) {
        bytes32[] memory q = new bytes32[](1);
        q[0] = slot;
        return uint256(IGBLIN(vault).extsload(q)[0]);
    }

    function _a(uint256 x) internal pure returns (address) {
        return address(uint160(x));
    }

    function _rowBase(uint256 i) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(S_BASKET))) + i * ROW_SLOTS;
    }

    function _readMany(address vault, uint256[] memory slots) internal view returns (uint256[] memory r) {
        bytes32[] memory q = new bytes32[](slots.length);
        for (uint256 i = 0; i < slots.length; ++i) {
            q[i] = bytes32(slots[i]);
        }
        bytes32[] memory b = IGBLIN(vault).extsload(q);
        r = new uint256[](b.length);
        for (uint256 i = 0; i < b.length; ++i) {
            r[i] = uint256(b[i]);
        }
    }

    /// @dev `token.balanceOf(account)` read with a gas-capped staticcall that copies at most one word; zero if the
    ///      token does not answer, as the vault reads it.
    function _balanceOf(address token, address account) internal view returns (uint256 b) {
        assembly ("memory-safe") {
            let m := mload(0x40)
            mstore(m, 0x70a0823100000000000000000000000000000000000000000000000000000000)
            mstore(add(m, 0x04), account)
            // Kept apart: Yul evaluates arguments right to left, so returndatasize() is read after the call.
            let r := staticcall(100000, token, m, 0x24, m, 0x20)
            b := mul(mload(m), and(r, gt(returndatasize(), 31)))
        }
    }

    /// @dev Value of `amt` units of a token with `d` decimals in wei of ETH, from the feeds' latest answers; zero if an
    ///      answer is not positive. `d` is the value the vault stored at listing.
    function _ethValue(uint8 d, address oracle, uint256 amt, address ethOracle) internal view returns (uint256) {
        if (amt == 0) return 0;
        (, int256 pA,,,) = AggregatorV3Interface(oracle).latestRoundData();
        (, int256 pE,,,) = AggregatorV3Interface(ethOracle).latestRoundData();
        if (pA <= 0 || pE <= 0) return 0;
        return d < 18
            ? (amt * uint256(pA) * (10 ** (18 - d))) / uint256(pE)
            : (amt * uint256(pA)) / (uint256(pE) * (10 ** (d - 18)));
    }
}
