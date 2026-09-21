// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {ERC20 as ERC20Base} from "solady/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {SignatureCheckerLib} from "solady/utils/SignatureCheckerLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC5267} from "@openzeppelin/contracts/interfaces/IERC5267.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IGBLIN} from "./interfaces/IGBLIN.sol";
import {IAuctionCallback} from "./interfaces/IAuctionCallback.sol";
import {AggregatorV3Interface} from "./interfaces/external/AggregatorV3Interface.sol";
import {IWETH} from "./interfaces/external/IWETH.sol";
import {OracleLib} from "./libraries/OracleLib.sol";
import {ShieldLib} from "./libraries/ShieldLib.sol";
import {Asset} from "./types/Asset.sol";

/// @title Global Balanced Liquidity Index (GBLIN)
/// @author GBLIN Protocol
/// @notice ERC-20 index token fully backed by a basket of assets held in this contract. Shares are minted at net asset
///         value (NAV) and redeemed pro rata in kind. The basket is priced with Chainlink feeds, protected by a crash
///         shield that reduces the weight of a falling asset, and brought back to its target weights by a Dutch auction
///         open to anyone.
/// @dev Accounting. Every token the vault holds belongs to exactly one of three sets:
///      - free: balance minus reserved, owned by the holders and counted in NAV;
///      - reserved (`reservedAmount`): redemption legs that could not be delivered, claimable with `claimPending`;
///      - quarantined (`abandonedMask`): balances of an abandoned row, which can no longer be priced and never count
///        again.
///      Prices come from Chainlink feeds only: no AMM price enters NAV, mints, redemptions or auction fills, and the
///      vault never swaps: a holder who wants ETH redeems in kind through a periphery contract that sells the legs.
///      Amounts of shares and assets paid out round down, in favour of the vault.
///      There is no proxy, no delegatecall and no selfdestruct; the owner is expected to be a timelock.
/// @custom:security-contact info@gblin.digital
contract GBLIN is IGBLIN, IERC5267, ERC20Base, ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    /// @dev An asset waiting for its listing delay.
    struct PendingAsset {
        address token;
        address oracle;
        bool isStable;
        uint256 baseWeight;
        uint256 executeAfter;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 private constant BPS = 10_000;
    /// @dev Virtual shares and assets in every NAV computation, so that no share can be bought at the price of dust.
    uint256 private constant VIRTUAL_SHARES = 1e6;
    uint256 private constant VIRTUAL_ASSETS = 1;
    /// @dev Time the sequencer must have been up before mints and bids are accepted again.
    uint256 private constant SEQUENCER_GRACE_PERIOD = 1 hours;
    /// @dev Oldest answer any conversion accepts; the stricter freshness windows apply on top of it.
    uint256 private constant PRICE_MAX_AGE = 26 hours;
    /// @dev Minimum silence of a feed before its delisted row can be abandoned.
    uint256 private constant ABANDON_MIN_SILENCE = 7 days;
    /// @dev Gas given to each token transfer of an in-kind redemption; a token that needs more becomes a credit.
    uint256 private constant TRANSFER_GAS = 300_000;

    /// @dev Hard bounds of the governance parameters, see `setParam`.
    uint256 private constant HARD_MAX_FEE_BPS = 100;
    uint256 private constant HARD_MAX_MANAGEMENT_FEE_BPS = 200;
    uint256 private constant HARD_MAX_AUCTION_BPS = 300;
    uint256 private constant HARD_MAX_ORACLE_AGE = 6 hours;
    uint256 private constant HARD_MAX_BASKET = 50;
    uint256 private constant MAX_NEW_ASSET_WEIGHT = 3000;
    uint256 private constant HARD_MAX_VOL_MULT = 100_000;
    uint256 private constant HARD_MAX_WINDOW = 30 days;
    uint256 private constant HARD_MAX_MIN_DEPOSIT = 10 ether;
    uint256 private constant HARD_MAX_INKIND_BPS = 300;
    uint256 private constant HARD_MAX_INKIND_TAX = 500;

    /// @dev Number of values of each `setParam` key, four bits per key with key 0 in the lowest nibble. Zero: no such
    ///      key.
    uint256 private constant PARAM_ARITY = 0x10110120402212132400;

    bytes32 private constant TRANSFER_WITH_AUTHORIZATION_TYPEHASH =
        0x7c7c6cdb67a18743f49ec6fa9b35f50d52ed05cbed4cc592e13b44501c1a2267;
    bytes32 private constant RECEIVE_WITH_AUTHORIZATION_TYPEHASH =
        0xd099cc98ef71107a616c4f0f941f04c322d8e254fe26b3c6668db87aae413de8;
    bytes32 private constant CANCEL_AUTHORIZATION_TYPEHASH =
        0x158b0a9edf7a828aad02f63cd515c68ef2f50ba807396f6d12842833a1597429;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGBLIN
    address public immutable WETH;

    /// @dev In-kind mint fee: floor, and extra charged in proportion to how far the deposit moves the asset from target
    ///      (bps).
    uint256 internal inKindFeeBps = 50;
    uint256 internal inKindTaxBps = 150;
    /// @dev ETH/USD feed; every asset feed must have the same decimals.
    address internal wethOracle;
    /// @dev L2 sequencer uptime feed, or the sentinel in front of it. Zero disables the check.
    address internal sequencerFeed;
    /// @inheritdoc IGBLIN
    address public owner;
    /// @dev Receives the protocol fee and the management fee, as shares.
    address internal feeRecipient;
    /// @dev Mint fees in bps of the deposit: the protocol fee is minted as shares to `feeRecipient`, the stability fee
    ///      stays in NAV.
    uint256 internal protocolFeeBps = 5;
    uint256 internal stabilityFeeBps = 5;
    uint256 internal minDeposit;
    /// @dev Maximum feed age for pricing, and the stricter age required to move value (auction fills).
    uint256 internal oracleTimeout = 2 hours;
    uint256 internal maxOracleAgeTrade = 30 minutes;

    /// @dev Crash shield parameters, see `ShieldLib.refresh`.
    uint256 internal baseCrashThresholdBps = 1500;
    uint256 internal crashVolMultiplier = 5000;
    uint256 internal recoveryBandBps = 800;
    uint256 internal slashMultiplier = 2000;
    uint256 internal peakDecayPerDayBps = 50;
    uint256 internal slowPeakDecayPerDayBps = 15;
    uint256 internal fullSlashDrawdownBps = 3000;
    uint256 internal minCrashBps = 1500;
    uint256 internal maxCrashBps = 5000;
    uint256 internal pegBandBps = 200;

    /// @dev An auction opens when the largest deviation from target exceeds `driftBandBps` of NAV, and closes once the
    ///      deviation is at or below `driftCloseBps`.
    uint256 internal driftBandBps = 700;
    uint256 internal driftCloseBps = 175;
    /// @dev Auction price curve: `auctionStartBps` below the oracle price at opening, rising to `auctionCapBps` above
    ///      it over `auctionRamp`, held there for another `auctionRamp`, then starting again.
    uint256 internal auctionStartBps = 100;
    uint256 internal auctionCapBps = 50;
    uint256 internal auctionRamp = 1 hours;
    /// @dev Minimum interval between two updates of the shield's volatility estimate.
    uint256 internal volUpdateInterval = 1 hours;

    /// @dev Basket rows. Indices never change: delisted rows stay in place.
    Asset[] internal basket;
    PendingAsset internal proposedAsset;

    /// @dev Opening time of the current auction; zero when none is open.
    uint256 internal driftSince;
    uint256 internal lastVolRefresh;
    /// @dev holder => token => claimable amount.
    mapping(address => mapping(address => uint256)) internal pendingWithdrawal;
    /// @dev token => total owed to claimants, excluded from the free balance.
    mapping(address => uint256) internal reservedAmount;
    /// @dev Bit `i` set: row `i` is abandoned, permanently.
    uint256 internal abandonedMask;
    /// @inheritdoc IGBLIN
    address public pendingOwner;
    /// @dev Seconds a holder must wait after minting for itself before redeeming.
    uint256 internal sellCooldown = 20 seconds;
    mapping(address => uint256) internal lastDepositTime;
    uint256 internal maxBasketSize = 20;
    uint256 internal assetListingDelay = 48 hours;
    /// @inheritdoc IGBLIN
    mapping(address => mapping(bytes32 => bool)) public authorizationState;
    /// @dev Annual management fee in bps of the supply, minted to `feeRecipient` pro rata over time.
    uint256 internal managementFeeBps = 50;
    uint256 internal lastManagementFeeAccrual;
    /// @dev Bids through `bid` without paying at once, for CoW Protocol solvers to settle (`setAddress` key 6).
    address internal fillAgent;
    /// @dev True while the fill agent holds an open fill; the agent's balances of the fill's two tokens count in NAV
    ///      until the fill is closed.
    bool internal fillOpen;
    /// @dev Block in which the open fill was opened: only in that block may closing it revert.
    uint64 internal fillBlock;
    /// @dev Basket row of the open fill; together with WETH it names the fill's two tokens.
    uint8 internal fillIndex;
    /// @dev Direction of the open fill, as in `bid`.
    bool internal fillBuysAsset;
    /// @dev Output the vault sent for the open fill, and the least input due for all of it. Enough to tell from
    ///      balances alone whether a swap is under way, without asking the agent.
    uint128 internal fillAmountOut;
    uint128 internal fillAmountIn;

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function _checkOwner() internal view {
        if (msg.sender != owner) revert Unauthorized();
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice The deployer is the first owner and should hand over to a timelock with `transferOwnership`.
    /// @param _weth Wrapped ether.
    /// @param _wethOracle ETH/USD price feed.
    /// @param _sequencer Sequencer uptime feed or sentinel; zero disables the check.
    /// @param _feeRecipient Receiver of the protocol and management fees, paid as shares.
    constructor(address _weth, address _wethOracle, address _sequencer, address _feeRecipient) {
        if (_weth == address(0) || _feeRecipient == address(0) || _wethOracle == address(0)) revert InvalidAddress();

        if (_weth.code.length == 0 || _wethOracle.code.length == 0) revert InvalidAddress();
        if (_sequencer != address(0) && _sequencer.code.length == 0) revert ParamOutOfBounds();
        WETH = _weth;
        wethOracle = _wethOracle;
        sequencerFeed = _sequencer;
        feeRecipient = _feeRecipient;
        owner = msg.sender;
        lastVolRefresh = block.timestamp;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                                 ERC-20
    //////////////////////////////////////////////////////////////*/

    /// @notice Token name, also the EIP-712 domain name of permit and EIP-3009.
    function name() public pure override returns (string memory) {
        return "Global Balanced Liquidity Index";
    }

    /// @notice Token symbol.
    function symbol() public pure override returns (string memory) {
        return "GBLIN";
    }

    /// @inheritdoc IGBLIN
    function version() external pure returns (string memory) {
        return "1";
    }

    /// @notice Moves `amount` shares from the caller to `to`.
    /// @dev Reverts with `InvalidAddress` when `to` is the zero address.
    function transfer(address to, uint256 amount) public override returns (bool) {
        if (to == address(0)) revert InvalidAddress();
        return super.transfer(to, amount);
    }

    /// @notice Moves `amount` shares from `from` to `to` using the caller's allowance.
    /// @dev Reverts with `InvalidAddress` when `to` is the zero address.
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (to == address(0)) revert InvalidAddress();
        return super.transferFrom(from, to, amount);
    }

    /// @dev The Solady base grants Permit2 an infinite allowance on every holder by default; this token does not.
    function _givePermit2InfiniteAllowance() internal pure override returns (bool) {
        return false;
    }

    /*//////////////////////////////////////////////////////////////
                                EIP-3009
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGBLIN
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
    ) external {
        bytes32 digest = _useAuthorization(
            TRANSFER_WITH_AUTHORIZATION_TYPEHASH, from, to, value, validAfter, validBefore, nonce
        );
        if (_recoverSigner(digest, v, r, s) != from) revert AuthorizationInvalid();
        _transfer(from, to, value);
    }

    /// @inheritdoc IGBLIN
    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        bytes calldata signature
    ) external {
        bytes32 digest = _useAuthorization(
            TRANSFER_WITH_AUTHORIZATION_TYPEHASH, from, to, value, validAfter, validBefore, nonce
        );
        if (!SignatureCheckerLib.isValidSignatureNowCalldata(from, digest, signature)) revert AuthorizationInvalid();
        _transfer(from, to, value);
    }

    /// @inheritdoc IGBLIN
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
    ) external {
        if (msg.sender != to) revert AuthorizationInvalid();
        bytes32 digest =
            _useAuthorization(RECEIVE_WITH_AUTHORIZATION_TYPEHASH, from, to, value, validAfter, validBefore, nonce);
        if (_recoverSigner(digest, v, r, s) != from) revert AuthorizationInvalid();
        _transfer(from, to, value);
    }

    /// @inheritdoc IGBLIN
    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        bytes calldata signature
    ) external {
        if (msg.sender != to) revert AuthorizationInvalid();
        bytes32 digest =
            _useAuthorization(RECEIVE_WITH_AUTHORIZATION_TYPEHASH, from, to, value, validAfter, validBefore, nonce);
        if (!SignatureCheckerLib.isValidSignatureNowCalldata(from, digest, signature)) revert AuthorizationInvalid();
        _transfer(from, to, value);
    }

    /// @inheritdoc IGBLIN
    function cancelAuthorization(address authorizer, bytes32 nonce, uint8 v, bytes32 r, bytes32 s) external {
        bytes32 digest = _useCancellation(authorizer, nonce);
        if (_recoverSigner(digest, v, r, s) != authorizer) revert AuthorizationInvalid();
    }

    /// @inheritdoc IGBLIN
    function cancelAuthorization(address authorizer, bytes32 nonce, bytes calldata signature) external {
        bytes32 digest = _useCancellation(authorizer, nonce);
        if (!SignatureCheckerLib.isValidSignatureNowCalldata(authorizer, digest, signature)) {
            revert AuthorizationInvalid();
        }
    }

    /// @inheritdoc IERC5267
    function eip712Domain()
        external
        view
        returns (
            bytes1 fields,
            string memory name_,
            string memory version_,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        )
    {
        return (hex"0f", name(), "1", block.chainid, address(this), bytes32(0), new uint256[](0));
    }

    /// @dev Checks the validity window and the nonce of an EIP-3009 authorization, marks the nonce used, and returns
    ///      the EIP-712 digest the signature must cover. The caller verifies the signature.
    function _useAuthorization(
        bytes32 typeHash,
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce
    ) internal returns (bytes32) {
        if (
            block.timestamp <= validAfter || block.timestamp >= validBefore || from == address(0) || to == address(0)
                || authorizationState[from][nonce]
        ) revert AuthorizationInvalid();
        authorizationState[from][nonce] = true;
        emit AuthorizationUsed(from, nonce);
        return _hashTypedData(keccak256(abi.encode(typeHash, from, to, value, validAfter, validBefore, nonce)));
    }

    /// @dev Checks and marks the nonce of an EIP-3009 cancellation, and returns the EIP-712 digest the signature must
    ///      cover. The caller verifies the signature.
    function _useCancellation(address authorizer, bytes32 nonce) internal returns (bytes32) {
        if (authorizer == address(0) || authorizationState[authorizer][nonce]) revert AuthorizationInvalid();
        authorizationState[authorizer][nonce] = true;
        emit AuthorizationCanceled(authorizer, nonce);
        return _hashTypedData(keccak256(abi.encode(CANCEL_AUTHORIZATION_TYPEHASH, authorizer, nonce)));
    }

    /// @dev EIP-712 digest of `structHash` over the token's domain.
    function _hashTypedData(bytes32 structHash) internal view returns (bytes32 digest) {
        digest = DOMAIN_SEPARATOR();
        assembly ("memory-safe") {
            mstore(0x00, 0x1901000000000000)
            mstore(0x1a, digest)
            mstore(0x3a, structHash)
            digest := keccak256(0x18, 0x42)
            // Restores the part of the free memory pointer slot that was overwritten.
            mstore(0x3a, 0)
        }
    }

    /// @dev Signer of `digest` for an ECDSA signature, or a value that is never a signer when the signature is invalid
    ///      or has a high `s`.
    function _recoverSigner(bytes32 digest, uint8 v, bytes32 r, bytes32 s) internal view returns (address signer) {
        assembly ("memory-safe") {
            let m := mload(0x40)
            mstore(0x00, digest)
            mstore(0x20, and(0xff, v))
            mstore(0x40, r)
            mstore(0x60, s)
            pop(staticcall(gas(), 1, 0x00, 0x80, 0x20, 0x20))
            // A high s (above secp256k1n / 2) is rejected. Empty returndata makes the load read the digest, which is
            // never a signer.
            signer := mul(
                mload(returndatasize()),
                lt(s, 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A1)
            )
            mstore(0x40, m)
            mstore(0x60, 0)
        }
    }

    /*//////////////////////////////////////////////////////////////
                                  MINT
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGBLIN
    function buyGBLIN(uint256 minOut) external payable nonReentrant {
        if (msg.value == 0) revert InvalidAmount();
        IWETH(WETH).deposit{value: msg.value}();
        _mintGBLIN(msg.value, minOut, msg.sender);
    }

    /// @inheritdoc IGBLIN
    function buyGBLINWithWeth(uint256 amount, uint256 minOut, address receiver) external nonReentrant {
        if (receiver == address(0)) revert InvalidAddress();
        SafeTransferLib.safeTransferFrom(WETH, msg.sender, address(this), amount);
        _mintGBLIN(amount, minOut, receiver);
    }

    /// @inheritdoc IGBLIN
    function buyGBLINInKind(address token, uint256 amountIn, uint256 minOut) external nonReentrant {
        _checkSequencer();
        _requireFreshOracles();
        if (amountIn == 0) revert InvalidAmount();

        uint256 idx = _indexOf(token);
        Asset storage a = basket[idx];
        if (a.delisted) revert InvalidAmount();
        if (_oracleAge(a.oracle) > _maxAge(a.isStable, oracleTimeout)) revert PriceUnavailable();

        uint256 ethValue = _toEth(a, amountIn);
        if (ethValue < minDeposit) revert DepositTooSmall();

        _refreshShield();
        _accrueManagementFee();

        uint256 feeBps = _inKindFeeBps(idx, ethValue);
        uint256 supply = totalSupply() + VIRTUAL_SHARES;
        uint256 assets = totalEthValue(0) + VIRTUAL_ASSETS;
        uint256 netEth = ethValue - (ethValue * feeBps) / BPS;
        uint256 out = (netEth * supply) / assets;
        if (out == 0) revert ZeroOutput();
        if (out < minOut) revert SlippageExceeded();

        _pullExact(token, amountIn);

        _mint(msg.sender, out);
        {
            uint256 feeEth = (ethValue * protocolFeeBps) / BPS;
            _mintFeeShares((feeEth * supply) / assets, feeEth, 1);
        }

        lastDepositTime[msg.sender] = block.timestamp;
        _markDrift();
        emit Minted(msg.sender, ethValue, out);
    }

    /// @dev Mints shares to `receiver` for `wethAmount` of WETH the vault already holds.
    function _mintGBLIN(uint256 wethAmount, uint256 minOut, address receiver) internal {
        _checkSequencer();
        _requireFreshOracles();
        if (wethAmount < minDeposit) revert DepositTooSmall();

        _refreshShield();
        _accrueManagementFee();

        (uint256 out, uint256 feeShares) = _quoteBuy(wethAmount, wethAmount);
        if (out == 0) revert ZeroOutput();
        if (out < minOut) revert SlippageExceeded();

        _mint(receiver, out);
        _mintFeeShares(feeShares, (wethAmount * protocolFeeBps) / BPS, 0);

        if (receiver == msg.sender) lastDepositTime[receiver] = block.timestamp;
        _markDrift();
        emit Minted(receiver, wethAmount, out);
    }

    /// @dev Shares for a deposit of `ethValue`, priced on a NAV that leaves out `exWeth` (the WETH just deposited).
    function _quoteBuy(uint256 ethValue, uint256 exWeth) internal view returns (uint256 out, uint256 feeShares) {
        uint256 protocolFee = (ethValue * protocolFeeBps) / BPS;
        uint256 stabilityFee = (ethValue * stabilityFeeBps) / BPS;
        uint256 supply = totalSupply() + VIRTUAL_SHARES;
        uint256 assets = totalEthValue(exWeth) + VIRTUAL_ASSETS;
        out = ((ethValue - protocolFee - stabilityFee) * supply) / assets;
        feeShares = (protocolFee * supply) / assets;
    }

    /// @dev Mints fee shares to `feeRecipient`, priced like the deposit they come from; the value they stand for stays
    ///      in the vault. `kind` as in `FeeSharesMinted`.
    function _mintFeeShares(uint256 shares, uint256 ethValue, uint8 kind) internal {
        if (shares == 0) return;
        address recipient = feeRecipient;
        _mint(recipient, shares);
        emit FeeSharesMinted(recipient, kind, ethValue, shares);
    }

    /// @dev Management fee: `managementFeeBps` per year on the supply, pro rata to the time since the last accrual,
    ///      minted to `feeRecipient`. Runs on every mint, redemption, bid and `refreshWeights`; the first call starts
    ///      the clock.
    function _accrueManagementFee() internal {
        uint256 t = lastManagementFeeAccrual;
        lastManagementFeeAccrual = block.timestamp;
        if (t == 0 || block.timestamp <= t) return;
        uint256 s = totalSupply();
        if (s == 0 || managementFeeBps == 0) return;
        _mintFeeShares((s * managementFeeBps * (block.timestamp - t)) / (BPS * 365 days), 0, 2);
    }

    /// @dev In-kind mint fee of a deposit of `ethValue` into row `idx`, see `ShieldLib.inKindFee`.
    function _inKindFeeBps(uint256 idx, uint256 ethValue) internal view returns (uint256) {
        uint256 tot = totalEthValue(0);
        if (tot == 0) return inKindFeeBps;
        return ShieldLib.inKindFee(
            (tot * basket[idx].dynamicWeight) / BPS,
            _toEth(basket[idx], _freeBalance(basket[idx].token)),
            ethValue,
            inKindFeeBps,
            inKindTaxBps
        );
    }

    /*//////////////////////////////////////////////////////////////
                                 REDEEM
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGBLIN
    function sellGBLIN(uint256 gblinAmount) external nonReentrant {
        _settleAndWrap();
        (uint256 wethShare, uint256[] memory shares) = _initRedeem(gblinAmount);

        uint256 n = basket.length;
        for (uint256 i = 0; i < n; ++i) {
            uint256 amt = shares[i];
            if (amt == 0 || basket[i].token == WETH) continue;
            if (!_tryTransfer(basket[i].token, msg.sender, amt)) _credit(msg.sender, basket[i].token, amt, 1);
        }
        if (wethShare > 0) _sendEth(msg.sender, wethShare);
        emit Redeemed(msg.sender, gblinAmount);
    }

    /// @inheritdoc IGBLIN
    function claimPending(address token) external nonReentrant {
        uint256 amt = pendingWithdrawal[msg.sender][token];
        pendingWithdrawal[msg.sender][token] = 0;
        if (amt == 0) revert NothingToClaim();
        reservedAmount[token] -= amt;
        SafeTransferLib.safeTransfer(token, msg.sender, amt);
        emit RedemptionClaimed(msg.sender, token, amt);
    }

    /// @dev Accrues the management fee, checks the cooldown and the amount, computes the pro rata amounts and burns the
    ///      shares.
    function _initRedeem(uint256 gblinAmount) internal returns (uint256 wethShare, uint256[] memory shares) {
        _accrueManagementFee();
        if (block.timestamp < lastDepositTime[msg.sender] + sellCooldown) revert CooldownActive();
        if (gblinAmount == 0 || gblinAmount > balanceOf(msg.sender)) revert InvalidAmount();
        (wethShare, shares) = _preBurnShares(gblinAmount);
        _burn(msg.sender, gblinAmount);
    }

    /// @dev Pro rata amounts of free WETH and of every free, non-quarantined token balance, computed before the burn.
    function _preBurnShares(uint256 gblinAmount) internal view returns (uint256 wethShare, uint256[] memory shares) {
        uint256 supply = totalSupply() + VIRTUAL_SHARES;
        wethShare = (_holdersWeth() * gblinAmount) / supply;
        uint256 n = basket.length;
        shares = new uint256[](n);
        for (uint256 i = 0; i < n; ++i) {
            if (basket[i].token == WETH || (abandonedMask & (1 << i)) != 0) continue;
            shares[i] = (_freeBalance(basket[i].token) * gblinAmount) / supply;
        }
    }

    /*//////////////////////////////////////////////////////////////
                                AUCTION
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGBLIN
    function auctionPremiumBps() public view returns (int256) {
        // Casts are safe: start and cap are at most 300, `t` and `ramp` at most 30 days (`setParam` key 4).
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 start = -int256(auctionStartBps);
        uint256 since = driftSince;
        if (since == 0) return start;
        uint256 ramp = auctionRamp;
        uint256 t = (block.timestamp - since) % (2 * ramp);
        if (t > ramp) t = ramp;
        // forge-lint: disable-next-line(unsafe-typecast)
        return start + ((int256(auctionCapBps) - start) * int256(t)) / int256(ramp);
    }

    /// @inheritdoc IGBLIN
    function bid(uint256 index, bool vaultBuysAsset, uint256 amountIn, uint256 minOut, bytes calldata data)
        external
        nonReentrant
        returns (uint256 amountInUsed, uint256 amountOut)
    {
        _checkSequencer();
        _requireFreshOracles();
        _refreshShield();
        _accrueManagementFee();
        _markDrift();
        if (index >= basket.length) revert InvalidIndex();
        Asset storage a = basket[index];
        if (a.token == WETH || (abandonedMask & (1 << index)) != 0) revert InvalidIndex();
        uint256 since = driftSince;
        if (since == 0 || since == block.timestamp) revert NoAuction();

        uint256 target = (totalEthValue(0) * a.dynamicWeight) / BPS;
        uint256 cur = _tradeValue(a, _freeBalance(a.token), true);
        // The premium lies between -300 and 300 bps, so the factor is between 9700 and 10300.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 factor = uint256(int256(BPS) + auctionPremiumBps());
        address tokenIn;
        address tokenOut;

        if (vaultBuysAsset) {
            if (cur >= target) revert NoAuction();
            uint256 gap = target - cur;
            uint256 affordable = (_holdersWeth() * BPS) / factor;
            if (gap > affordable) gap = affordable;
            uint256 maxIn = _tradeValue(a, gap, false);
            if (amountIn > maxIn) amountIn = maxIn;
            amountOut = (_tradeValue(a, amountIn, true) * factor) / BPS;
            if (amountOut > _holdersWeth()) revert InvalidAmount();
            (tokenIn, tokenOut) = (a.token, WETH);
        } else {
            if (cur <= target) revert NoAuction();
            uint256 maxIn = ((cur - target) * BPS) / factor;
            if (amountIn > maxIn) amountIn = maxIn;
            amountOut = _tradeValue(a, (amountIn * factor) / BPS, false);
            if (amountOut > _freeBalance(a.token)) revert InvalidAmount();
            (tokenIn, tokenOut) = (WETH, a.token);
        }
        if (amountOut == 0) revert ZeroOutput();
        if (amountOut < minOut) revert SlippageExceeded();

        SafeTransferLib.safeTransfer(tokenOut, msg.sender, amountOut);
        if (data.length != 0) {
            IAuctionCallback(msg.sender).onAuctionFill(tokenIn, amountIn, tokenOut, amountOut, data);
        }
        if (msg.sender == fillAgent) {
            if (amountIn > type(uint128).max || amountOut > type(uint128).max) revert InvalidAmount();
            fillOpen = true;
            fillBlock = uint64(block.number);
            // The cast is safe: the basket never holds more than `HARD_MAX_BASKET` rows.
            fillIndex = uint8(index);
            fillBuysAsset = vaultBuysAsset;
            fillAmountOut = uint128(amountOut);
            fillAmountIn = uint128(amountIn);
            return (amountIn, amountOut);
        }
        _pullExact(tokenIn, amountIn);
        amountInUsed = amountIn;

        _markDrift();
        emit AuctionFill(msg.sender, tokenIn, tokenOut, amountIn, amountOut);
    }

    /// @inheritdoc IGBLIN
    function currentDriftEth() public view returns (uint256) {
        return _worstDrift(totalEthValue(0));
    }

    /// @inheritdoc IGBLIN
    function refreshWeights() public nonReentrant {
        _refreshShield();
        _accrueManagementFee();
        _markDrift();
    }

    /// @dev Largest |value - target| over every priced row except WETH (whose weight is the remainder). Delisted rows
    ///      and rows the shield cut to zero have a target of zero.
    function _worstDrift(uint256 tot) internal view returns (uint256 worst) {
        if (tot == 0) return 0;
        uint256 n = basket.length;
        for (uint256 i = 0; i < n; ++i) {
            Asset storage a = basket[i];
            if (a.token == WETH || (abandonedMask & (1 << i)) != 0) continue;
            uint256 target = (tot * a.dynamicWeight) / BPS;
            uint256 cur = _toEth(a, _freeBalance(a.token));
            uint256 d = cur > target ? cur - target : target - cur;
            if (d > worst) worst = d;
        }
    }

    /// @dev Opens the auction above the band and closes it at the closing threshold. Does nothing while the vault
    ///      cannot price itself, so a stale feed can neither open an auction nor restart its clock.
    function _markDrift() internal {
        uint256 tot = totalEthValue(0);
        if (tot == 0 || _isStale()) return;
        uint256 worst = _worstDrift(tot);
        uint256 driftBps = (worst * BPS) / tot;
        if (driftBps > driftBandBps) {
            if (driftSince == 0) {
                driftSince = block.timestamp;
                emit AuctionOpened(worst);
            }
        } else if (driftSince != 0 && driftBps <= driftCloseBps) {
            driftSince = 0;
            emit AuctionClosed();
        }
    }

    /// @dev Closes the open fill, if any: the agent sends back every unit of the two tokens, and reverts while a swap
    ///      has taken part of the vault's output without delivering the input, so no call that moves value can run
    ///      half-way through a swap. Runs first in `_settleAndWrap`, which every such call reaches before it reads a
    ///      balance.
    function _settleFill() internal {
        if (!fillOpen) return;
        fillOpen = false;
        fillIndex = 0;
        fillBuysAsset = false;
        fillAmountOut = 0;
        fillAmountIn = 0;
        address agent = fillAgent;
        uint256 openedAt = fillBlock;
        bool ok;
        address tokenIn;
        address tokenOut;
        uint256 bought;
        uint256 sold;
        // `close()` with at most 1,000,000 gas and four words of returndata. Only in the opening block does a failure
        // revert (a swap half-way); later a broken or hostile agent cannot keep any door of the vault shut.
        assembly ("memory-safe") {
            let m := mload(0x40)
            mstore(m, 0x43d726d600000000000000000000000000000000000000000000000000000000)
            ok := call(1000000, agent, 0, m, 0x04, m, 0x80)
            let n := returndatasize()
            if iszero(ok) {
                if eq(number(), openedAt) {
                    if gt(n, 0x80) { n := 0x80 }
                    revert(m, n)
                }
            }
            ok := and(ok, gt(n, 0x7f))
            if ok {
                tokenIn := and(mload(m), 0xffffffffffffffffffffffffffffffffffffffff)
                tokenOut := and(mload(add(m, 0x20)), 0xffffffffffffffffffffffffffffffffffffffff)
                bought := mload(add(m, 0x40))
                sold := mload(add(m, 0x60))
            }
        }
        // A fill the agent already cleared on its own reports no tokens and needs no event.
        if (ok && tokenIn != address(0)) emit AuctionFill(agent, tokenIn, tokenOut, bought, sold);
    }

    /// @dev The two tokens of the open fill, the vault's output first. One of them is always WETH.
    function _fillTokens() internal view returns (address tokenOut, address tokenIn) {
        address asset = basket[fillIndex].token;
        return fillBuysAsset ? (WETH, asset) : (asset, WETH);
    }

    /// @dev True if `token` is one of the two tokens of the open fill.
    function _isFillToken(address token) internal view returns (bool) {
        return token == WETH || token == basket[fillIndex].token;
    }

    /// @dev True while a swap has taken part of the output of the open fill without delivering the input due for it.
    ///      Read from balances alone: the vault never asks the agent whether it is half way through a swap, so a
    ///      broken or hostile agent can neither hide one nor make this read fail. A token that does not answer counts
    ///      as zero, which reports a swap under way and makes the vault call itself unpriceable.
    function _swapActive() internal view returns (bool) {
        if (!fillOpen || block.number != fillBlock) return false;
        (address tokenOut, address tokenIn) = _fillTokens();
        uint256 sent = fillAmountOut;
        (uint256 left,) = _balanceOfChecked(tokenOut, fillAgent);
        if (left >= sent) return false;
        // Input due for the part already taken, rounded up. Both factors are at most `type(uint128).max`, so the
        // product always fits.
        uint256 due = ((sent - left) * fillAmountIn + sent - 1) / sent;
        (uint256 got,) = _balanceOfChecked(tokenIn, fillAgent);
        return due > got;
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGBLIN
    function totalEthValue(uint256 excludeWeth) public view returns (uint256 total) {
        uint256 w = _holdersWeth();
        total = w > excludeWeth ? w - excludeWeth : 0;
        uint256 n = basket.length;
        for (uint256 i = 0; i < n; ++i) {
            if (basket[i].token == WETH) continue;
            uint256 bal = _freeBalance(basket[i].token);
            if (bal > 0 && (abandonedMask & (1 << i)) == 0) total += _toEth(basket[i], bal);
        }
    }

    /// @inheritdoc IGBLIN
    function navPerShare(uint256 excludeWeth) public view returns (uint256) {
        uint256 supply = totalSupply() + VIRTUAL_SHARES;
        uint256 assets = totalEthValue(excludeWeth) + VIRTUAL_ASSETS;
        return (assets * 1 ether) / supply;
    }

    /// @inheritdoc IGBLIN
    function isNavReliable() external view returns (bool) {
        return !_isStale() && !_swapActive();
    }

    /// @inheritdoc IGBLIN
    function extsload(bytes32[] calldata slots) external view returns (bytes32[] memory res) {
        res = new bytes32[](slots.length);
        for (uint256 i = 0; i < slots.length; ++i) {
            bytes32 slot = slots[i];
            assembly ("memory-safe") {
                mstore(add(res, mul(add(i, 1), 32)), sload(slot))
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                               GOVERNANCE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGBLIN
    function proposeAsset(address token, address oracle, bool isStable, uint256 baseWeight) external onlyOwner {
        if (token == address(0) || oracle == address(0)) revert InvalidAddress();
        _sameScale(oracle);

        if (token.code.length == 0) revert TokenNotConformant();
        uint8 d = IERC20Metadata(token).decimals();
        if (d < 6 || d > 18) revert TokenNotConformant();
        if (baseWeight == 0 || baseWeight > MAX_NEW_ASSET_WEIGHT) revert WeightOutOfBounds();
        if (basket.length >= maxBasketSize) revert ParamOutOfBounds();

        uint256 sum = baseWeight;
        for (uint256 i = 0; i < basket.length; ++i) {
            if (basket[i].token == token) revert AssetAlreadyExists();
            sum += basket[i].baseWeight;
        }
        if (sum > BPS) revert WeightOutOfBounds();
        if (_price(oracle) == 0) revert PriceUnavailable();

        bytes32 idEth = _oracleId(wethOracle);
        if (token != WETH && idEth != bytes32(0) && _oracleId(oracle) == idEth) revert ParamOutOfBounds();
        proposedAsset = PendingAsset(token, oracle, isStable, baseWeight, block.timestamp + assetListingDelay);
        emit AssetProposed(token, proposedAsset.executeAfter);
    }

    /// @inheritdoc IGBLIN
    function executeAssetAddition(uint256 probe) external nonReentrant onlyOwner {
        PendingAsset storage p = proposedAsset;
        if (p.executeAfter == 0) revert NoAssetProposed();
        if (block.timestamp < p.executeAfter) revert ListingDelayActive();
        uint256 price = _price(p.oracle);
        if (price == 0) revert PriceUnavailable();

        uint256 sum = p.baseWeight;
        for (uint256 i = 0; i < basket.length; ++i) {
            sum += basket[i].baseWeight;
        }
        if (sum > BPS) revert WeightOutOfBounds();

        if (basket.length >= maxBasketSize) revert ParamOutOfBounds();
        if (probe == 0) revert InvalidAmount();
        uint8 tokenDecimals = IERC20Metadata(p.token).decimals();
        if (tokenDecimals < 6 || tokenDecimals > 18) revert TokenNotConformant();
        _pullExact(p.token, probe);

        basket.push(
            Asset({
                token: p.token,
                decimals: tokenDecimals,
                oracle: p.oracle,
                isStable: p.isStable,
                delisted: false,
                baseWeight: p.baseWeight,
                dynamicWeight: p.baseWeight,
                peakPrice: price,
                lastPeakUpdate: block.timestamp,
                slowPeakPrice: price,
                slowLastPeakUpdate: block.timestamp,
                lastObservedPrice: price,
                ewmaVolBps: 0,
                shielded: false,
                pegPrice: p.isStable ? price : 0
            })
        );
        emit AssetAdded(p.token, p.baseWeight);
        delete proposedAsset;
        _refreshShield();
    }

    /// @inheritdoc IGBLIN
    function assetAction(uint256 k, uint256 i) external nonReentrant onlyOwner {
        if (i >= basket.length) revert InvalidIndex();
        Asset storage a = basket[i];
        if (k == 1) {
            a.baseWeight = 0;
            a.dynamicWeight = 0;
            a.delisted = true;
            emit AssetDelisted(a.token);
            _refreshShield();
        } else if (k == 2) {
            if ((abandonedMask & (1 << i)) != 0) revert InvalidIndex();
            a.delisted = false;
            emit AssetRelisted(a.token);
            _refreshShield();
        } else if (k == 3) {
            if (!a.delisted) revert InvalidAmount();
            if (_price(a.oracle) != 0 || block.timestamp - a.lastPeakUpdate < ABANDON_MIN_SILENCE) {
                revert ParamOutOfBounds();
            }
            abandonedMask |= (1 << i);
            if (navPerShare(0) == 0) revert ParamOutOfBounds();
            emit AssetAbandoned(a.token);
        } else {
            revert ParamOutOfBounds();
        }
    }

    /// @inheritdoc IGBLIN
    function setParam(uint256 k, uint256[7] calldata v) external onlyOwner {
        uint256 n = (PARAM_ARITY >> (k * 4)) & 0xF;
        if (n == 0) revert ParamOutOfBounds();
        uint256 unused;
        for (uint256 i = n; i < 7; ++i) {
            unused |= v[i];
        }
        if (unused != 0) revert ParamOutOfBounds();

        if (k == 3) {
            if (v[0] + v[1] > HARD_MAX_FEE_BPS || v[0] > inKindFeeBps) revert ParamOutOfBounds();
            protocolFeeBps = v[0];
            stabilityFeeBps = v[1];
        } else if (k == 5) {
            if (v[0] > HARD_MAX_MIN_DEPOSIT) revert ParamOutOfBounds();
            minDeposit = v[0];
        } else if (k == 6) {
            if (v[0] > HARD_MAX_ORACLE_AGE || v[1] > v[0] || v[0] < 10 minutes || v[1] < 1 minutes) {
                revert ParamOutOfBounds();
            }
            oracleTimeout = v[0];
            maxOracleAgeTrade = v[1];
        } else if (k == 2) {
            if (v[3] > BPS) revert ParamOutOfBounds();
            if (v[0] == 0 || v[0] >= fullSlashDrawdownBps) revert ParamOutOfBounds();
            if (v[1] > HARD_MAX_VOL_MULT) revert ParamOutOfBounds();
            if (v[2] >= minCrashBps) revert ParamOutOfBounds();
            baseCrashThresholdBps = v[0];
            crashVolMultiplier = v[1];
            recoveryBandBps = v[2];
            slashMultiplier = v[3];
        } else if (k == 9) {
            if (v[0] > BPS) revert ParamOutOfBounds();
            if (v[1] == 0 || v[1] > BPS) revert ParamOutOfBounds();
            if (v[1] <= minCrashBps || v[1] <= baseCrashThresholdBps) revert ParamOutOfBounds();
            slowPeakDecayPerDayBps = v[0];
            fullSlashDrawdownBps = v[1];
        } else if (k == 8) {
            if (v[0] == 0 || v[0] > BPS || v[1] >= v[0]) revert ParamOutOfBounds();
            driftBandBps = v[0];
            driftCloseBps = v[1];
        } else if (k == 13) {
            if (v[0] < protocolFeeBps || v[0] > HARD_MAX_INKIND_BPS || v[1] > HARD_MAX_INKIND_TAX) {
                revert ParamOutOfBounds();
            }
            inKindFeeBps = v[0];
            inKindTaxBps = v[1];
        } else if (k == 4) {
            if (v[0] == 0 || v[0] > HARD_MAX_AUCTION_BPS || v[1] > HARD_MAX_AUCTION_BPS) revert ParamOutOfBounds();
            if (v[2] < 1 minutes || v[2] > HARD_MAX_WINDOW) revert ParamOutOfBounds();
            auctionStartBps = v[0];
            auctionCapBps = v[1];
            auctionRamp = v[2];
        } else if (k == 11) {
            if (v[0] == 0 || v[0] > v[1] || v[1] > BPS || v[2] > BPS) revert ParamOutOfBounds();
            if (v[3] == 0 || v[3] > HARD_MAX_WINDOW) revert ParamOutOfBounds();
            if (recoveryBandBps >= v[0] || fullSlashDrawdownBps <= v[0]) revert ParamOutOfBounds();
            minCrashBps = v[0];
            maxCrashBps = v[1];
            peakDecayPerDayBps = v[2];
            volUpdateInterval = v[3];
        } else if (k == 7) {
            if (v[0] > 1000) revert ParamOutOfBounds();
            pegBandBps = v[0];
        } else if (k == 14) {
            if (v[0] > 1 hours) revert ParamOutOfBounds();
            sellCooldown = v[0];
        } else if (k == 16) {
            if (v[0] > HARD_MAX_BASKET || v[0] < basket.length) revert ParamOutOfBounds();
            maxBasketSize = v[0];
        } else if (k == 17) {
            if (v[0] > HARD_MAX_WINDOW) revert ParamOutOfBounds();
            assetListingDelay = v[0];
        } else if (k == 19) {
            if (v[0] > HARD_MAX_MANAGEMENT_FEE_BPS) revert ParamOutOfBounds();
            _accrueManagementFee();
            managementFeeBps = v[0];
        }

        emit ParamUpdated(k, v);
    }

    /// @inheritdoc IGBLIN
    function setBaseWeights(uint256[] calldata w) external nonReentrant onlyOwner {
        if (w.length != basket.length) revert ParamOutOfBounds();
        uint256 sum;
        for (uint256 i = 0; i < w.length; ++i) {
            sum += w[i];
        }
        if (sum > BPS) revert WeightOutOfBounds();
        for (uint256 i = 0; i < w.length; ++i) {
            if (basket[i].delisted && w[i] != 0) revert WeightOutOfBounds();
            basket[i].baseWeight = w[i];
        }
        _refreshShield();
        emit BaseWeightsUpdated(w);
    }

    /// @inheritdoc IGBLIN
    function setAddress(uint256 k, address a) external nonReentrant onlyOwner {
        if (k == 2) {
            if (a != address(0) && a.code.length == 0) revert ParamOutOfBounds();
            sequencerFeed = a;
            emit SequencerFeedUpdated(a);
        } else if (k == 3) {
            if (a == address(0)) revert InvalidAddress();
            _accrueManagementFee();
            feeRecipient = a;
            emit FeeRecipientUpdated(a);
        } else if (k == 5) {
            _sameScale(a);
            _requireSameIdentity(wethOracle, a);
            if (_price(a) == 0) revert PriceUnavailable();
            emit OracleUpdated(WETH, wethOracle, a);
            wethOracle = a;
        } else if (k == 6) {
            if (a != address(0) && (a.code.length == 0 || a == address(this))) revert ParamOutOfBounds();
            _settleFill();
            fillAgent = a;
            emit FillAgentUpdated(a);
        } else {
            revert ParamOutOfBounds();
        }
    }

    /// @inheritdoc IGBLIN
    function transferOwnership(address newOwner) external onlyOwner {
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    /// @inheritdoc IGBLIN
    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert Unauthorized();
        emit OwnershipTransferred(owner, msg.sender);
        owner = msg.sender;
        pendingOwner = address(0);
    }

    /// @inheritdoc IGBLIN
    function updateOracle(uint256 i, address newOracle) external onlyOwner {
        if (i >= basket.length) revert InvalidIndex();
        _sameScale(newOracle);
        Asset storage a = basket[i];
        _requireSameIdentity(a.oracle, newOracle);
        uint256 p = _price(newOracle);
        if (p == 0) revert PriceUnavailable();
        emit OracleUpdated(a.token, a.oracle, newOracle);
        a.oracle = newOracle;
        a.peakPrice = p;
        a.lastPeakUpdate = block.timestamp;
        a.slowPeakPrice = p;
        a.slowLastPeakUpdate = block.timestamp;
        a.lastObservedPrice = p;
        a.ewmaVolBps = 0;
        a.shielded = false;
    }

    /// @notice Accepts ETH from WETH unwrapping. Any other ETH is wrapped into NAV by the next mint, redemption, bid or
    ///         `refreshWeights`.
    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                           ORACLES AND PRICES
    //////////////////////////////////////////////////////////////*/

    function _oracleAge(address o) internal view returns (uint256) {
        return OracleLib.age(o);
    }

    /// @dev Freshness window of a feed: `strictLimit`, or `PRICE_MAX_AGE` for the slow feed of a stable asset.
    function _maxAge(bool stableFeed, uint256 strictLimit) internal pure returns (uint256) {
        return stableFeed ? PRICE_MAX_AGE : strictLimit;
    }

    function _price(address o) internal view returns (uint256) {
        return OracleLib.price(o, PRICE_MAX_AGE);
    }

    /// @dev Requires a feed with the ETH feed's decimals that exposes a Chainlink aggregator.
    function _sameScale(address o) internal view {
        OracleLib.requireSameScale(o, wethOracle);
        if (!OracleLib.hasAggregator(o)) revert ParamOutOfBounds();
    }

    /// @dev Hash of the feed's `description()`, or zero if it has none.
    function _oracleId(address o) internal view returns (bytes32) {
        (bool ok, bytes memory d) = o.staticcall{gas: 30_000}(abi.encodeWithSelector(0x7284e416));
        return (ok && d.length > 64) ? keccak256(d) : bytes32(0);
    }

    /// @dev Requires `newFeed` to declare the same description as `oldFeed`, when `oldFeed` declares one.
    function _requireSameIdentity(address oldFeed, address newFeed) internal view {
        bytes32 id = _oracleId(oldFeed);
        if (id != bytes32(0) && id != _oracleId(newFeed)) revert ParamOutOfBounds();
    }

    function _requireFreshOracles() internal view {
        if (_isStale()) revert PriceUnavailable();
    }

    /// @dev True if the ETH feed is older than `oracleTimeout`, or a non-abandoned row holding a free balance has a
    ///      feed older than its window, or a basket token does not answer `balanceOf`.
    function _isStale() internal view returns (bool) {
        if (_oracleAge(wethOracle) > oracleTimeout) return true;
        uint256 n = basket.length;
        for (uint256 i = 0; i < n; ++i) {
            if (basket[i].token == WETH || (abandonedMask & (1 << i)) != 0) continue;
            (uint256 freeBal, bool ok) = _freeBalanceChecked(basket[i].token);
            if (!ok) return true;
            if (freeBal == 0) continue;
            if (_oracleAge(basket[i].oracle) > _maxAge(basket[i].isStable, oracleTimeout)) return true;
        }
        return false;
    }

    /// @dev Reverts while the sequencer is down or less than `SEQUENCER_GRACE_PERIOD` after it came back up.
    function _checkSequencer() internal view {
        if (sequencerFeed == address(0)) return;
        (, int256 answer, uint256 startedAt, uint256 updatedAt,) =
            AggregatorV3Interface(sequencerFeed).latestRoundData();
        if (answer == 1 || startedAt == 0 || updatedAt == 0) revert SequencerDown();
        if (startedAt > block.timestamp || block.timestamp - startedAt <= SEQUENCER_GRACE_PERIOD) {
            revert SequencerDown();
        }
    }

    function _convert(Asset storage a, uint256 amt, bool intoEth) internal view returns (uint256) {
        return OracleLib.convert(a.token, a.decimals, a.oracle, amt, WETH, wethOracle, PRICE_MAX_AGE, intoEth);
    }

    function _toEth(Asset storage a, uint256 amt) internal view returns (uint256) {
        return _convert(a, amt, true);
    }

    /// @dev Conversion for moving value: the ETH feed and the asset's feed must be within `maxOracleAgeTrade` (a stable
    ///      asset's feed within its slow window). Reverts with `PriceUnavailable` otherwise. Rounds down.
    function _tradeValue(Asset storage a, uint256 amt, bool intoEth) internal view returns (uint256) {
        bool ethStale = _oracleAge(wethOracle) > maxOracleAgeTrade;
        bool assetStale = _oracleAge(a.oracle) > _maxAge(a.isStable, maxOracleAgeTrade);
        if (ethStale || assetStale) revert PriceUnavailable();
        return _convert(a, amt, intoEth);
    }

    /*//////////////////////////////////////////////////////////////
                         BALANCES AND TRANSFERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Basket row of `token`; reverts if the token is not listed.
    function _indexOf(address token) internal view returns (uint256) {
        uint256 n = basket.length;
        for (uint256 i = 0; i < n; ++i) {
            if (basket[i].token == token) return i;
        }
        revert InvalidIndex();
    }

    /// @dev WETH owned by the holders: balance, plus the WETH of an open fill, minus WETH credits. WETH is always one
    ///      of the two tokens of a fill, so no further check is needed here.
    function _holdersWeth() internal view returns (uint256) {
        uint256 w = IWETH(WETH).balanceOf(address(this));
        if (fillOpen) w += IWETH(WETH).balanceOf(fillAgent);
        uint256 committed = reservedAmount[WETH];
        return w > committed ? w - committed : 0;
    }

    function _freeBalance(address token) internal view returns (uint256 b) {
        (b,) = _freeBalanceChecked(token);
    }

    /// @dev Balance minus reserved, and whether the token answered. While a fill is open the agent's balance is added
    ///      for the fill's two tokens only: any other balance left with the agent stays out of NAV until it is sent
    ///      back, so NAV never counts a token twice nor changes with the opening of an unrelated fill.
    function _freeBalanceChecked(address token) internal view returns (uint256 b, bool ok) {
        (b, ok) = _balanceOfChecked(token, address(this));
        if (fillOpen && _isFillToken(token)) {
            (uint256 f, bool fok) = _balanceOfChecked(token, fillAgent);
            b += f;
            ok = ok && fok;
        }
        uint256 reserved = reservedAmount[token];
        b = b > reserved ? b - reserved : 0;
    }

    /// @dev `token.balanceOf(account)` read with a gas-capped staticcall that copies at most one word, so a token that
    ///      reverts, burns gas or returns a huge payload counts as zero and makes the vault report itself unpriceable
    ///      instead of blocking redemptions.
    function _balanceOfChecked(address token, address account) internal view returns (uint256 b, bool ok) {
        assembly ("memory-safe") {
            let m := mload(0x40)
            mstore(m, 0x70a0823100000000000000000000000000000000000000000000000000000000)
            mstore(add(m, 0x04), account)
            // Kept apart: Yul evaluates arguments right to left, so returndatasize() must be read after the call.
            let r := staticcall(100000, token, m, 0x24, m, 0x20)
            ok := and(r, gt(returndatasize(), 31))
            b := mul(mload(m), ok)
        }
    }

    /// @dev Pulls `amt` of `token` from the caller and requires the vault's balance to grow by exactly `amt`.
    function _pullExact(address token, uint256 amt) internal {
        uint256 before = IERC20(token).balanceOf(address(this));
        SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), amt);
        if (IERC20(token).balanceOf(address(this)) - before != amt) revert TokenNotConformant();
    }

    /// @dev ERC-20 transfer that reports failure instead of reverting, reading at most one word of returndata. The
    ///      token gets at most `TRANSFER_GAS`, so one that burns gas costs the caller a bounded amount. A failure while
    ///      less than that allowance was available reverts instead, so a short gas limit cannot turn a leg into a
    ///      credit.
    function _tryTransfer(address token, address to, uint256 amt) internal returns (bool ok) {
        bool starved;
        assembly ("memory-safe") {
            let m := mload(0x40)
            mstore(m, 0xa9059cbb00000000000000000000000000000000000000000000000000000000)
            mstore(add(m, 0x04), and(to, 0xffffffffffffffffffffffffffffffffffffffff))
            mstore(add(m, 0x24), amt)
            // 63/64 of what is left must cover the allowance, with room for the cost of the call itself.
            starved := lt(gas(), add(TRANSFER_GAS, 10000))
            ok := call(TRANSFER_GAS, token, 0, m, 0x44, m, 0x20)
            let n := returndatasize()
            ok := and(ok, or(iszero(n), and(gt(n, 31), iszero(iszero(mload(m))))))
        }
        if (!ok && starved) revert InsufficientGas();
    }

    /// @dev Unwraps and sends ETH; if the receiver refuses it, the WETH is kept as a credit.
    function _sendEth(address to, uint256 amt) internal {
        IWETH(WETH).withdraw(amt);
        (bool ok,) = payable(to).call{value: amt}("");
        if (ok) return;
        IWETH(WETH).deposit{value: amt}();
        _credit(to, WETH, amt, 3);
    }

    /// @dev Credits `amt` of `token` to `holder` and reserves it out of the free balance.
    function _credit(address holder, address token, uint256 amt, uint8 reasonCode) internal {
        pendingWithdrawal[holder][token] += amt;
        reservedAmount[token] += amt;
        emit RedemptionCredited(holder, token, amt, reasonCode);
    }

    /*//////////////////////////////////////////////////////////////
                              CRASH SHIELD
    //////////////////////////////////////////////////////////////*/

    /// @dev Closes the open fill and wraps stray ETH.
    function _settleAndWrap() internal {
        _settleFill();
        uint256 bal = address(this).balance;
        if (bal > 0) IWETH(WETH).deposit{value: bal}();
    }

    /// @dev Closes the open fill, wraps stray ETH, then recomputes every row's dynamic weight from current prices (see
    ///      `ShieldLib.refresh`).
    function _refreshShield() internal {
        _settleAndWrap();

        uint256 n = basket.length;
        uint256[] memory prices = new uint256[](n);
        for (uint256 i = 0; i < n; ++i) {
            prices[i] = _price(basket[i].oracle);
        }
        bool updateVol = block.timestamp >= lastVolRefresh + volUpdateInterval;
        ShieldLib.refresh(
            basket,
            prices,
            ShieldLib.Params({
                baseCrashThresholdBps: baseCrashThresholdBps,
                crashVolMultiplier: crashVolMultiplier,
                recoveryBandBps: recoveryBandBps,
                slashMultiplier: slashMultiplier,
                peakDecayPerDayBps: peakDecayPerDayBps,
                slowPeakDecayPerDayBps: slowPeakDecayPerDayBps,
                fullSlashDrawdownBps: fullSlashDrawdownBps,
                minCrashBps: minCrashBps,
                maxCrashBps: maxCrashBps,
                pegBandBps: pegBandBps,
                updateVol: updateVol
            })
        );
        if (updateVol) lastVolRefresh = block.timestamp;
    }
}
