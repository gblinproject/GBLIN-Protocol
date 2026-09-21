// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @title IGBLIN
/// @author GBLIN Protocol
/// @notice Interface of the Global Balanced Liquidity Index (GBLIN): an ERC-20 index token fully backed by a basket of
///         assets held in the contract, minted at net asset value (NAV) and redeemed pro rata in kind.
/// @dev The token also implements ERC-20 and ERC-2612, which are not repeated here. Amounts of value are in wei of ETH,
///      weights and fees in basis points (bps, 1/10000).
interface IGBLIN {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice The L2 sequencer is down or restarted less than an hour ago, or the sentinel reports it down.
    error SequencerDown();
    /// @notice The output is below the caller's minimum.
    error SlippageExceeded();
    /// @notice The caller is not allowed to perform this action.
    error Unauthorized();
    /// @notice The caller minted for itself less than the redemption cooldown ago.
    error CooldownActive();
    /// @notice No auction is open, it opened in this block, or the asset is not on the requested side of the trade.
    error NoAuction();
    /// @notice A price feed this action needs is missing, stale or out of bounds, or a basket token did not answer.
    error PriceUnavailable();
    /// @notice The zero address, or an address without code where a contract is required.
    error InvalidAddress();
    /// @notice The basket index does not exist or refers to a row this action does not accept.
    error InvalidIndex();
    /// @notice The amount is zero, exceeds what is available, or is not acceptable in the current state.
    error InvalidAmount();
    /// @notice The deposit is below the minimum deposit.
    error DepositTooSmall();
    /// @notice There is nothing to claim.
    error NothingToClaim();
    /// @notice The token did not move the exact amount requested, has no code, or has unsupported decimals.
    error TokenNotConformant();
    /// @notice The operation would mint zero shares or deliver zero tokens.
    error ZeroOutput();
    /// @notice A governance value is outside its hard bounds, or the unused values of a parameter group are not zero.
    error ParamOutOfBounds();
    /// @notice The listing delay of the proposed asset has not elapsed.
    error ListingDelayActive();
    /// @notice No asset is currently proposed.
    error NoAssetProposed();
    /// @notice The asset is already in the basket.
    error AssetAlreadyExists();
    /// @notice The weight is zero, above the cap for a new asset, or the weights would exceed 100%.
    error WeightOutOfBounds();
    /// @notice The EIP-3009 authorization is invalid, outside its validity window, already used, or submitted by the
    ///         wrong caller.
    error AuthorizationInvalid();
    /// @notice Too little gas was left to give a redemption transfer its full gas allowance.
    error InsufficientGas();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Shares were minted.
    /// @param receiver Account that received the shares.
    /// @param value Value of the deposit in wei of ETH.
    /// @param shares Shares minted to `receiver`.
    event Minted(address indexed receiver, uint256 value, uint256 shares);

    /// @notice Shares were redeemed in kind.
    /// @param holder Account whose shares were burned.
    /// @param shares Shares burned.
    event Redeemed(address indexed holder, uint256 shares);

    /// @notice A redemption leg could not be delivered and was credited to the holder instead.
    /// @param holder Account credited.
    /// @param token Token of the credit; WETH for refused ETH.
    /// @param amount Amount credited.
    /// @param reason 1 the token transfer failed, 3 the holder refused the ETH.
    event RedemptionCredited(address indexed holder, address indexed token, uint256 amount, uint8 reason);

    /// @notice A credit was claimed.
    /// @param holder Account that claimed.
    /// @param token Token claimed.
    /// @param amount Amount transferred.
    event RedemptionClaimed(address indexed holder, address indexed token, uint256 amount);

    /// @notice An auction trade was settled.
    /// @param bidder Account that traded with the vault.
    /// @param tokenIn Token the vault received.
    /// @param tokenOut Token the vault sent.
    /// @param amountIn Amount of `tokenIn` received.
    /// @param amountOut Amount of `tokenOut` sent.
    event AuctionFill(
        address indexed bidder, address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut
    );

    /// @notice The largest deviation from the target weights exceeded the opening band: an auction is open.
    /// @param driftEth Largest deviation of any row from its target value, in wei of ETH.
    event AuctionOpened(uint256 driftEth);

    /// @notice The largest deviation fell to the closing threshold: the auction is closed.
    event AuctionClosed();

    /// @notice An asset was proposed for listing.
    /// @param token Asset proposed.
    /// @param executeAfter Time from which the asset can be added.
    event AssetProposed(address indexed token, uint256 executeAfter);

    /// @notice An asset was added to the basket.
    /// @param token Asset added.
    /// @param baseWeight Base weight of the asset, in bps.
    event AssetAdded(address indexed token, uint256 baseWeight);

    /// @notice A basket row was delisted: its weights are zero and its balance is sold through the auction.
    /// @param token Asset of the row.
    event AssetDelisted(address indexed token);

    /// @notice A delisted basket row was relisted.
    /// @param token Asset of the row.
    event AssetRelisted(address indexed token);

    /// @notice A delisted basket row was abandoned: its balance is quarantined and never counts in NAV again.
    /// @param token Asset of the row.
    event AssetAbandoned(address indexed token);

    /// @notice A parameter group changed.
    /// @param key Key of the group, as in `setParam`.
    /// @param values Values written, as passed to `setParam`.
    event ParamUpdated(uint256 indexed key, uint256[7] values);

    /// @notice The base weights changed.
    /// @param weights Base weight of every row, in bps.
    event BaseWeightsUpdated(uint256[] weights);

    /// @notice The fill agent changed.
    /// @param newAgent New fill agent; zero when none is set.
    event FillAgentUpdated(address indexed newAgent);

    /// @notice The sequencer uptime feed changed.
    /// @param newFeed New feed; zero disables the check.
    event SequencerFeedUpdated(address indexed newFeed);

    /// @notice A price feed changed.
    /// @param token Asset whose feed changed; WETH for the ETH/USD feed.
    /// @param oldOracle Previous feed.
    /// @param newOracle New feed.
    event OracleUpdated(address indexed token, address indexed oldOracle, address indexed newOracle);

    /// @notice The fee recipient changed.
    /// @param newRecipient New fee recipient.
    event FeeRecipientUpdated(address indexed newRecipient);

    /// @notice Fee shares were minted to the fee recipient.
    /// @param recipient Fee recipient that received the shares.
    /// @param kind 0 protocol fee of an ETH or WETH mint, 1 protocol fee of an in-kind mint, 2 management fee.
    /// @param value Value of the fee in wei of ETH; zero for the management fee.
    /// @param shares Shares minted.
    event FeeSharesMinted(address indexed recipient, uint8 kind, uint256 value, uint256 shares);

    /// @notice The owner designated a new owner, who must call `acceptOwnership`.
    /// @param previousOwner Current owner.
    /// @param newOwner Designated owner.
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);

    /// @notice Ownership changed.
    /// @param previousOwner Previous owner.
    /// @param newOwner New owner.
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /// @notice EIP-3009: an authorization was used.
    /// @param authorizer Signer of the authorization.
    /// @param nonce Nonce of the authorization.
    event AuthorizationUsed(address indexed authorizer, bytes32 indexed nonce);

    /// @notice EIP-3009: an authorization was canceled.
    /// @param authorizer Signer of the authorization.
    /// @param nonce Nonce of the authorization.
    event AuthorizationCanceled(address indexed authorizer, bytes32 indexed nonce);

    /*//////////////////////////////////////////////////////////////
                               ACCOUNTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Wrapped ether: unit of account and currency of ETH mints, ETH redemptions and auction fills.
    function WETH() external view returns (address);

    /// @notice Governance account.
    function owner() external view returns (address);

    /// @notice Account designated to become the owner; zero when none is designated.
    function pendingOwner() external view returns (address);

    /*//////////////////////////////////////////////////////////////
                               EIP-3009
    //////////////////////////////////////////////////////////////*/

    /// @notice EIP-712 domain version of permit and EIP-3009 authorizations.
    function version() external pure returns (string memory);

    /// @notice True once `nonce` of `authorizer` has been used or canceled.
    /// @param authorizer Signer of the authorization.
    /// @param nonce Nonce of the authorization.
    function authorizationState(address authorizer, bytes32 nonce) external view returns (bool);

    /// @notice Transfers `value` shares from `from` to `to` with a signature of `from` (EIP-3009).
    /// @dev Valid strictly after `validAfter` and strictly before `validBefore`; each nonce can be used once across all
    ///      authorization functions. ECDSA signatures with a high `s` are rejected. Emits `AuthorizationUsed`.
    /// @param from Payer and signer.
    /// @param to Payee; not the zero address.
    /// @param value Shares to transfer.
    /// @param validAfter Unix time after which the authorization is valid.
    /// @param validBefore Unix time before which the authorization is valid.
    /// @param nonce Unique nonce chosen by the signer.
    /// @param v Signature recovery byte.
    /// @param r Signature r.
    /// @param s Signature s.
    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /// @notice Same as `transferWithAuthorization`, with the signature as bytes, so that smart contract accounts can
    ///         authorize transfers (ERC-1271).
    /// @dev If `from` has code the signature is checked with `isValidSignature` on `from`; otherwise it must be a
    ///      65-byte or a 64-byte (EIP-2098) ECDSA signature of `from`.
    /// @param from Payer and signer.
    /// @param to Payee; not the zero address.
    /// @param value Shares to transfer.
    /// @param validAfter Unix time after which the authorization is valid.
    /// @param validBefore Unix time before which the authorization is valid.
    /// @param nonce Unique nonce chosen by the signer.
    /// @param signature Signature of `from`.
    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        bytes calldata signature
    ) external;

    /// @notice Same as `transferWithAuthorization`, but only `to` can submit it, so the transfer cannot be front-run.
    /// @param from Payer and signer.
    /// @param to Payee; must be the caller.
    /// @param value Shares to transfer.
    /// @param validAfter Unix time after which the authorization is valid.
    /// @param validBefore Unix time before which the authorization is valid.
    /// @param nonce Unique nonce chosen by the signer.
    /// @param v Signature recovery byte.
    /// @param r Signature r.
    /// @param s Signature s.
    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /// @notice Same as `receiveWithAuthorization`, with the signature as bytes (ERC-1271), checked as in the bytes
    ///         variant of `transferWithAuthorization`.
    /// @param from Payer and signer.
    /// @param to Payee; must be the caller.
    /// @param value Shares to transfer.
    /// @param validAfter Unix time after which the authorization is valid.
    /// @param validBefore Unix time before which the authorization is valid.
    /// @param nonce Unique nonce chosen by the signer.
    /// @param signature Signature of `from`.
    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        bytes calldata signature
    ) external;

    /// @notice Cancels an unused authorization with a signature of its authorizer (EIP-3009).
    /// @param authorizer Signer of the authorization.
    /// @param nonce Nonce to cancel.
    /// @param v Signature recovery byte.
    /// @param r Signature r.
    /// @param s Signature s.
    function cancelAuthorization(address authorizer, bytes32 nonce, uint8 v, bytes32 r, bytes32 s) external;

    /// @notice Same as `cancelAuthorization`, with the signature as bytes (ERC-1271), checked as in the bytes variant
    ///         of `transferWithAuthorization`.
    /// @param authorizer Signer of the authorization.
    /// @param nonce Nonce to cancel.
    /// @param signature Signature of `authorizer`.
    function cancelAuthorization(address authorizer, bytes32 nonce, bytes calldata signature) external;

    /*//////////////////////////////////////////////////////////////
                                  MINT
    //////////////////////////////////////////////////////////////*/

    /// @notice Mints shares with ETH at NAV.
    /// @dev The deposit is wrapped and stays in the vault as WETH; the auction brings the basket back to its weights.
    ///      Fees: the protocol fee, minted as shares to the fee recipient, and the stability fee, left in NAV. Starts
    ///      the caller's redemption cooldown. Requires the sequencer up and every price feed fresh.
    /// @param minOut Minimum shares the caller accepts.
    function buyGBLIN(uint256 minOut) external payable;

    /// @notice Mints shares to `receiver` with `amount` WETH pulled from the caller, on the same terms as `buyGBLIN`.
    /// @dev Only a mint for oneself starts the redemption cooldown, so a third party cannot keep a holder's
    ///      redemptions locked by minting dust for it.
    /// @param amount WETH to deposit.
    /// @param minOut Minimum shares the receiver accepts.
    /// @param receiver Account that receives the shares.
    function buyGBLINWithWeth(uint256 amount, uint256 minOut, address receiver) external;

    /// @notice Mints shares by depositing a basket asset.
    /// @dev The fee never falls below the in-kind floor and grows with how far the deposit moves the asset away from
    ///      its target weight. The protocol fee part is minted as shares to the fee recipient; the rest stays in NAV.
    ///      The token must move the exact amount. Starts the caller's redemption cooldown.
    /// @param token Basket asset to deposit; not delisted.
    /// @param amountIn Amount of `token`.
    /// @param minOut Minimum shares the caller accepts.
    function buyGBLINInKind(address token, uint256 amountIn, uint256 minOut) external;

    /*//////////////////////////////////////////////////////////////
                                 REDEEM
    //////////////////////////////////////////////////////////////*/

    /// @notice Redeems `gblinAmount` shares of the caller for their pro rata part of every free basket balance, without
    ///         fee. The WETH part is paid in ETH.
    /// @dev Reads no price feed and no token metadata, so a broken feed or token cannot block it, and is never paused.
    ///      The crash shield and the auction state are updated by the next call that prices the basket. A leg that
    ///      cannot be transferred within its gas allowance, and ETH the caller refuses, become credits claimable with
    ///      `claimPending`. A leg whose token does not answer `balanceOf` is not delivered and creates no credit.
    ///      An open fill of the fill agent is closed first; only in the block that opened it can a close that fails
    ///      revert this call, and only for that block.
    ///      A leg counts as delivered when its token reports the transfer as successful. The vault does not read the
    ///      recipient's balance afterwards, so an asset that hands over less than the amount asked short-changes the
    ///      redeemer without the vault seeing it; listing an asset assumes it never does, see `proposeAsset`. The
    ///      check is left out on purpose: reading a balance here would give this call, the one call that must always
    ///      go through, a new way to fail.
    /// @param gblinAmount Shares to redeem.
    function sellGBLIN(uint256 gblinAmount) external;

    /// @notice Claims a credit left by a redemption leg that could not be delivered.
    /// @param token Token of the credit; WETH for refused ETH.
    function claimPending(address token) external;

    /*//////////////////////////////////////////////////////////////
                                AUCTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Premium of the auction now, in bps of the oracle value, earned by whoever trades toward the target
    ///         weights.
    /// @dev A negative value is a discount the bidder gives the vault. While an auction is open the premium rises
    ///      linearly from minus the start discount to the cap over the ramp, holds at the cap for another ramp, and the
    ///      curve then starts again. Returns minus the start discount when no auction is open.
    /// @return Premium in bps.
    function auctionPremiumBps() external view returns (int256);

    /// @notice Trades with the vault toward the target weight of basket row `index`, at the oracle price adjusted by
    ///         the current auction premium.
    /// @dev If `vaultBuysAsset` the caller gives the asset and receives WETH; otherwise it gives WETH and receives the
    ///      asset. The input is reduced to what closes the gap to the target, so a bid never pushes the asset past its
    ///      target, and, when the vault buys, to what the holders' WETH can pay. The output is sent first; if `data` is
    ///      not empty the vault then calls `IAuctionCallback(msg.sender).onAuctionFill`, and finally pulls the exact
    ///      input from the caller. From the fill agent it pulls nothing: the fill stays open, counted in NAV, until the
    ///      next call that moves value closes it. Rounding favours the vault. Requires an auction opened in an earlier
    ///      block, the sequencer up, every feed fresh, the ETH feed and the asset's feed within the trade window, and a
    ///      row that is neither WETH nor abandoned. While the call runs the vault is locked and its views read an
    ///      intermediate state.
    /// @param index Basket row.
    /// @param vaultBuysAsset True to sell the asset to the vault for WETH; false to buy the asset from the vault.
    /// @param amountIn Maximum input; `type(uint256).max` closes the whole gap.
    /// @param minOut Minimum output the caller accepts.
    /// @param data Data passed to the caller's callback; empty for a plain bid.
    /// @return amountInUsed Input pulled from the caller or, for the fill agent, owed by the open fill.
    /// @return amountOut Output sent to the caller.
    function bid(uint256 index, bool vaultBuysAsset, uint256 amountIn, uint256 minOut, bytes calldata data)
        external
        returns (uint256 amountInUsed, uint256 amountOut);

    /// @notice Largest deviation of any basket row from its target value, in wei of ETH.
    function currentDriftEth() external view returns (uint256);

    /// @notice Closes an open fill, updates the crash shield, accrues the management fee, and opens or closes the
    ///         auction. Anyone can call.
    function refreshWeights() external;

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @notice Value of the holders' free balances in wei of ETH, at oracle prices.
    /// @param excludeWeth Amount of the holders' WETH to leave out; zero for the full value.
    /// @return total Value in wei of ETH.
    function totalEthValue(uint256 excludeWeth) external view returns (uint256 total);

    /// @notice Value of one share (1e18 units) in wei of ETH, including the virtual shares and assets.
    /// @param excludeWeth As in `totalEthValue`.
    function navPerShare(uint256 excludeWeth) external view returns (uint256);

    /// @notice False while a feed the NAV depends on is stale, a basket token does not answer, or an open fill is half
    ///         way through a swap in this block. While false, quotes are not reliable and mints and bids revert.
    /// @dev Read from feeds and balances only, never from the fill agent, so no contract the vault holds at arm's
    ///      length can make this call fail or hide a swap under way.
    function isNavReliable() external view returns (bool);

    /// @notice Reads raw storage slots.
    /// @param slots Slots to read.
    /// @return res One word per slot, in order.
    function extsload(bytes32[] calldata slots) external view returns (bytes32[] memory res);

    /*//////////////////////////////////////////////////////////////
                               GOVERNANCE
    //////////////////////////////////////////////////////////////*/

    /// @notice Proposes a new basket asset, which can be added once the listing delay has elapsed.
    /// @dev The feed must have the ETH feed's decimals, expose an aggregator, answer with a live price and not declare
    ///      the ETH feed's identity; the token must have code and between 6 and 18 decimals.
    ///      Listing also assumes a property the contract cannot enforce: for as long as it stays in the basket, the
    ///      asset delivers to the recipient the whole amount a transfer asks for, with no fee, burn or other
    ///      reduction. The listing probe proves it only for the moment it runs. An asset that later stops honouring
    ///      it breaks this assumption, and the holders' remedy is governance: delist the row and let the auction sell
    ///      it, or abandon it once its feed is silent.
    /// @param token Asset to list.
    /// @param oracle USD price feed of the asset.
    /// @param isStable True for an asset whose feed updates slowly and whose peg the shield watches.
    /// @param baseWeight Initial weight in bps, at most 3000; the weights must not exceed 10000.
    function proposeAsset(address token, address oracle, bool isStable, uint256 baseWeight) external;

    /// @notice Adds the proposed asset once its listing delay has elapsed.
    /// @dev Pulls `probe` units from the caller and requires the exact amount to arrive, which rejects fee-on-transfer
    ///      tokens and keeps the vault from ever being empty. The token's decimals are read once and stored.
    /// @param probe Units of the asset to transfer in; must be positive.
    function executeAssetAddition(uint256 probe) external;

    /// @notice Acts on a basket row. `k`: 1 delist, 2 relist, 3 abandon.
    /// @dev Delisting sets the weights to zero and keeps the row: its balance stays in NAV and is sold through the
    ///      auction. Relisting reopens a delisted row and leaves its weights at zero, so `setBaseWeights` has to give
    ///      it a weight again; it is refused for an abandoned row. Abandoning quarantines a delisted row forever,
    ///      whatever it holds, so that tokens sent to a dead row cannot keep it in the basket; it requires a feed
    ///      without a price and silent for 7 days, and a positive NAV afterwards. The owner's timelock gives holders
    ///      the time to redeem the row in kind first.
    /// @param k Action.
    /// @param i Basket row.
    function assetAction(uint256 k, uint256 i) external;

    /// @notice Sets one parameter group. Every value of the group is written; the unused values must be zero.
    /// @dev Keys and hard bounds (any other key reverts):
    ///      2  crash shield: base threshold (0 < x < full slash), volatility multiplier (<= 100000),
    ///         recovery band (< min crash), slash multiplier (<= 10000)
    ///      3  mint fees: protocol, stability (sum <= 100, protocol <= in-kind floor)
    ///      4  auction: start discount (1 to 300), cap premium (<= 300), ramp (1 minute to 30 days)
    ///      5  minimum deposit (<= 10 ether)
    ///      6  feed ages: pricing (10 minutes to 6 hours), trading (1 minute to the pricing age)
    ///      7  peg band of stable assets (<= 1000)
    ///      8  auction band: opening threshold (1 to 10000), closing threshold (below the opening one)
    ///      9  shield curve: slow peak decay per day (<= 10000), full-slash drawdown (above min crash and base
    ///         threshold)
    ///      11 shield tuning: min crash (above recovery band, below full slash), max crash, peak decay per day,
    ///         volatility update interval (1 second to 30 days)
    ///      13 in-kind fee: floor (protocol fee to 300), deviation tax (<= 500)
    ///      14 redemption cooldown (<= 1 hour)
    ///      16 basket size cap (current length to 50)
    ///      17 listing delay (<= 30 days)
    ///      19 management fee per year (<= 200), accrued at the previous rate first
    ///      Emits `ParamUpdated`.
    /// @param k Key.
    /// @param v Values; the ones the key does not use must be zero.
    function setParam(uint256 k, uint256[7] calldata v) external;

    /// @notice Sets the base weight of every row, in bps. Emits `BaseWeightsUpdated`.
    /// @param w One weight per row; the sum must not exceed 10000 and delisted rows must be zero.
    function setBaseWeights(uint256[] calldata w) external;

    /// @notice Sets one of the vault's addresses. `k`: 2 sequencer feed, 3 fee recipient, 5 ETH price feed, 6 fill
    ///         agent. Any other key reverts.
    /// @dev The sequencer feed and the fill agent must have code or be zero; the fill agent cannot be the vault, and
    ///      changing it closes an open fill first. The fee recipient cannot be zero, and the management fee accrued so
    ///      far is minted to the current recipient before it changes. A new ETH feed must have the same decimals and
    ///      declared identity as the current one and answer with a live price.
    /// @param k Key.
    /// @param a New address.
    function setAddress(uint256 k, address a) external;

    /// @notice Designates `newOwner`, who takes over by calling `acceptOwnership`. The zero address cancels a pending
    ///         transfer. Only the owner.
    /// @param newOwner Account designated to become the owner.
    function transferOwnership(address newOwner) external;

    /// @notice Completes an ownership transfer; only the designated owner can call it.
    function acceptOwnership() external;

    /// @notice Replaces the price feed of basket row `i` and resets its shield history.
    /// @dev The new feed must have the same decimals and declared identity as the old one, expose an aggregator and
    ///      answer with a live price. There is no band on the price change: the guards are identity, scale, freshness
    ///      and the owner's timelock.
    /// @param i Basket row.
    /// @param newOracle New USD price feed.
    function updateOracle(uint256 i, address newOracle) external;
}
