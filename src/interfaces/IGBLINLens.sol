// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IGBLINLens
/// @author GBLIN Protocol
/// @notice Read-only helper for the GBLIN vault: accounting, addresses, quotes, configuration and auction state.
/// @dev Every function takes the vault as its first argument.
interface IGBLINLens {
    /*//////////////////////////////////////////////////////////////
                               ACCOUNTING
    //////////////////////////////////////////////////////////////*/

    /// @notice Number of basket rows, delisted and abandoned rows included.
    /// @param vault GBLIN vault.
    function basketLength(address vault) external view returns (uint256);

    /// @notice Opening time of the current auction; zero when none is open.
    /// @param vault GBLIN vault.
    function auctionOpenedAt(address vault) external view returns (uint256);

    /// @notice Last update of the crash shield's volatility estimate.
    /// @param vault GBLIN vault.
    function lastVolRefresh(address vault) external view returns (uint256);

    /// @notice Credit of `holder` in `token`, left by a redemption leg that could not be delivered.
    /// @param vault GBLIN vault.
    /// @param holder Account credited.
    /// @param token Token of the credit.
    function pendingWithdrawal(address vault, address holder, address token) external view returns (uint256);

    /// @notice Total credits owed in `token`.
    /// @param vault GBLIN vault.
    /// @param token Token of the credits.
    function reservedAmount(address vault, address token) external view returns (uint256);

    /// @notice Bitmask of abandoned rows: bit `i` set means row `i` is abandoned.
    /// @param vault GBLIN vault.
    function abandonedMask(address vault) external view returns (uint256);

    /// @notice Last time `holder` minted for itself, from which its redemption cooldown runs.
    /// @param vault GBLIN vault.
    /// @param holder Account.
    function lastDepositTime(address vault, address holder) external view returns (uint256);

    /// @notice True while a locked call on the vault is executing; its views then read an intermediate state.
    /// @param vault GBLIN vault.
    function reentrancyLocked(address vault) external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                               ADDRESSES
    //////////////////////////////////////////////////////////////*/

    /// @notice ETH/USD price feed.
    /// @param vault GBLIN vault.
    function wethOracle(address vault) external view returns (address);

    /// @notice Sequencer uptime feed or sentinel; zero when the check is disabled.
    /// @param vault GBLIN vault.
    function sequencerFeed(address vault) external view returns (address);

    /// @notice Receiver of the protocol and management fees.
    /// @param vault GBLIN vault.
    function feeRecipient(address vault) external view returns (address);

    /// @notice Account designated to become the owner; zero when none is designated.
    /// @param vault GBLIN vault.
    function pendingOwner(address vault) external view returns (address);

    /*//////////////////////////////////////////////////////////////
                                 QUOTES
    //////////////////////////////////////////////////////////////*/

    /// @notice Shares a deposit of `ethValue` wei of ETH would mint, and the two mint fees.
    /// @dev Same arithmetic as the vault's ETH mint, with the management fee accrued since the last accrual and the
    ///      stray ETH the mint wraps first. Reverts with `IGBLIN.PriceUnavailable` while the vault cannot price itself.
    /// @param vault GBLIN vault.
    /// @param ethValue Deposit in wei of ETH.
    /// @return out Shares minted to the depositor.
    /// @return protocolFee Protocol fee in wei of ETH, minted as shares to the fee recipient.
    /// @return stabilityFee Stability fee in wei of ETH, left in NAV.
    function quoteBuy(address vault, uint256 ethValue)
        external
        view
        returns (uint256 out, uint256 protocolFee, uint256 stabilityFee);

    /// @notice Value in wei of ETH of `gblinAmount` shares at NAV.
    /// @dev With the management fee accrued since the last accrual and stray ETH, as a redemption counts them. Reverts
    ///      with `IGBLIN.PriceUnavailable` while the vault cannot price itself.
    /// @param vault GBLIN vault.
    /// @param gblinAmount Shares.
    function quoteSell(address vault, uint256 gblinAmount) external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                             CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Fee, feed-age, cooldown and basket-size settings.
    /// @param vault GBLIN vault.
    /// @return protocolFee Protocol fee of a mint, in bps.
    /// @return stabilityFee Stability fee of a mint, in bps.
    /// @return minDeposit Minimum deposit in wei of ETH.
    /// @return oracleAge Maximum feed age for pricing, in seconds.
    /// @return oracleAgeTrade Maximum feed age for auction trades, in seconds.
    /// @return sellCooldown Redemption cooldown after a mint for oneself, in seconds.
    /// @return basketCap Maximum number of basket rows.
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
        );

    /// @notice Crash shield settings, in bps unless stated.
    /// @param vault GBLIN vault.
    /// @return baseCrashThreshold Drawdown that activates the shield before the volatility adjustment.
    /// @return volMultiplier Weight of the volatility estimate in the threshold.
    /// @return recoveryBand Drawdown below which an active shield deactivates.
    /// @return slashMultiplier Share of the weight kept at full severity.
    /// @return peakDecayPerDay Daily decay of the fast peak.
    /// @return slowPeakDecayPerDay Daily decay of the slow peak.
    /// @return fullSlashDrawdown Drawdown at which the cut reaches full severity.
    /// @return minCrash Lower bound of the activation threshold.
    /// @return maxCrash Upper bound of the activation threshold.
    /// @return pegBand Band around the peg within which a stable asset receives slashed weight.
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
        );

    /// @notice Auction, listing, in-kind fee and volatility settings.
    /// @param vault GBLIN vault.
    /// @return driftBand Deviation from target, in bps of NAV, above which an auction opens.
    /// @return driftClose Deviation at or below which the auction closes.
    /// @return auctionStart Discount in bps at which the auction starts.
    /// @return auctionCap Premium in bps at which the auction holds.
    /// @return auctionRamp Seconds from the start discount to the cap premium.
    /// @return volUpdateInterval Minimum seconds between two updates of the volatility estimate.
    /// @return listingDelay Seconds between a proposal and the addition of an asset.
    /// @return inKindFee Floor of the in-kind mint fee, in bps.
    /// @return inKindTax Deviation tax of the in-kind mint fee, in bps.
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
        );

    /// @notice Annual management fee in bps of the supply.
    /// @param vault GBLIN vault.
    function managementFeeBps(address vault) external view returns (uint256);

    /// @notice Time of the last accrual of the management fee.
    /// @param vault GBLIN vault.
    function lastManagementFeeAccrual(address vault) external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                           BASKET AND AUCTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Stored fields of basket row `i`.
    /// @dev Reverts with `IGBLIN.InvalidIndex` for a row the basket does not have, rather than reading the slots that
    ///      index would land on and answering with a row that does not exist.
    /// @param vault GBLIN vault.
    /// @param i Basket row.
    /// @return token Asset of the row.
    /// @return oracle USD price feed of the asset.
    /// @return isStable True for a stable asset.
    /// @return delisted True for a delisted row.
    /// @return baseWeight Governance weight in bps.
    /// @return dynamicWeight Weight after the crash shield, in bps.
    /// @return shielded True while the crash shield is active on the row.
    /// @return abandoned True for an abandoned row.
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
        );

    /// @notice Auction state of basket row `i`.
    /// @dev Indicative: the conversion reads the feeds' latest answers without the vault's freshness checks. The
    ///      balance excludes credits owed in the token and includes an open fill, as in the vault. A bid on the
    ///      returned side for up to `gapEth` of value is what the vault accepts if its own checks pass. WETH and
    ///      abandoned rows return a zero gap.
    /// @param vault GBLIN vault.
    /// @param i Basket row.
    /// @return open True while an auction is open.
    /// @return premiumBps Current premium in bps.
    /// @return vaultBuysAsset Side the vault needs for this row.
    /// @return gapEth Gap to the target value in wei of ETH.
    function auction(address vault, uint256 i)
        external
        view
        returns (bool open, int256 premiumBps, bool vaultBuysAsset, uint256 gapEth);

    /// @notice Fill agent of the vault and whether it holds an open fill.
    /// @dev While a fill is open the agent's balances count in NAV for the fill's two tokens only; check
    ///      `IGBLIN.isNavReliable` before relying on a quote in the same block.
    /// @param vault GBLIN vault.
    /// @return agent Fill agent; zero when none is set.
    /// @return open True while a fill is open.
    function fill(address vault) external view returns (address agent, bool open);
}
