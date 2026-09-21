// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {AggregatorV3Interface} from "./interfaces/external/AggregatorV3Interface.sol";

/// @title Sequencer sentinel
/// @author GBLIN Protocol
/// @notice Stands between the GBLIN vault and the L2 sequencer uptime feed. It passes the real feed through unchanged
///         and lets a guardian report the sequencer as down at once. While it reports down, the vault refuses mints and
///         auction fills; redemptions, in kind or to ETH, and credit claims are not affected. A pause always expires.
/// @dev The guardian's pauses have a budget: one stretch of at most `MAX_PAUSE` from its start, renewals included, then
///      `GUARDIAN_REST` before it can pause again. A stretch the owner opens or extends belongs to the owner. The
///      owner, expected to be a timelock, is not budgeted but each of its calls is capped at `MAX_PAUSE`.
/// @custom:security-contact info@gblin.digital
contract SequencerSentinel is AggregatorV3Interface {
    /// @notice The caller is neither the owner nor the guardian, or the guardian's budget does not allow the action.
    error Unauthorized();
    /// @notice The zero address, or a feed without code.
    error InvalidAddress();
    /// @notice A pause of zero seconds.
    error InvalidAmount();

    /// @notice A pause started or was extended until `until`.
    event Paused(address indexed caller, uint256 until);
    /// @notice The pause was lifted.
    event Resumed(address indexed caller);
    /// @notice The guardian changed.
    event GuardianChanged(address indexed previousGuardian, address indexed newGuardian);
    /// @notice The owner designated `newOwner`, who must call `acceptOwnership`.
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    /// @notice Ownership changed.
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /// @notice Longest stretch of a pause.
    uint256 public constant MAX_PAUSE = 30 days;
    /// @notice Rest the guardian must observe after its stretch ends.
    uint256 public constant GUARDIAN_REST = 7 days;

    /// @notice The real sequencer uptime feed.
    AggregatorV3Interface public immutable feed;
    /// @notice Account that can pause without a budget and appoint the guardian.
    address public owner;
    /// @notice Account designated to become the owner.
    address public pendingOwner;
    /// @notice Account that can pause within its budget.
    address public guardian;
    /// @notice End of the current pause; zero or past when not paused.
    uint256 public pausedUntil;
    /// @notice Start of the current stretch of pauses.
    uint256 public pauseStartedAt;
    /// @notice End of the guardian's last stretch, from which its rest is counted.
    uint256 public lastGuardianPauseEnd;
    /// @notice True if the current stretch was opened by the guardian.
    bool public pausedByGuardian;

    /// @param _feed Real sequencer uptime feed.
    /// @param _guardian Initial guardian.
    constructor(address _feed, address _guardian) {
        if (_feed == address(0) || _guardian == address(0)) revert InvalidAddress();
        uint256 size;
        assembly { size := extcodesize(_feed) }
        if (size == 0) revert InvalidAddress();
        feed = AggregatorV3Interface(_feed);
        guardian = _guardian;
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    function _onlyOwnerOrGuardian() internal view {
        if (msg.sender != owner && msg.sender != guardian) revert Unauthorized();
    }

    /// @notice True while a pause is active.
    function isPaused() public view returns (bool) {
        return block.timestamp < pausedUntil;
    }

    /// @notice Reports the sequencer as down for `duration` seconds.
    /// @dev The owner can always pause, capped at `MAX_PAUSE` per call, and takes over any active stretch. The guardian
    ///      can open a stretch after its rest, extend only its own stretch, and never beyond `MAX_PAUSE` from its
    ///      start.
    /// @param duration Seconds, trimmed to the caller's limit.
    function pause(uint256 duration) external {
        _onlyOwnerOrGuardian();
        if (duration == 0) revert InvalidAmount();
        bool active = isPaused();
        if (msg.sender == owner) {
            if (duration > MAX_PAUSE) duration = MAX_PAUSE;
            if (!active) pauseStartedAt = block.timestamp;
            else if (pausedByGuardian) lastGuardianPauseEnd = block.timestamp;
            pausedByGuardian = false;
            pausedUntil = block.timestamp + duration;
        } else {
            if (!active) {
                if (block.timestamp < lastGuardianPauseEnd + GUARDIAN_REST) revert Unauthorized();
                pauseStartedAt = block.timestamp;
                pausedByGuardian = true;
            } else if (!pausedByGuardian) {
                revert Unauthorized();
            }
            uint256 cap = pauseStartedAt + MAX_PAUSE;
            if (block.timestamp >= cap) revert Unauthorized();
            if (block.timestamp + duration > cap) duration = cap - block.timestamp;
            pausedUntil = block.timestamp + duration;
            lastGuardianPauseEnd = pausedUntil;
        }
        emit Paused(msg.sender, pausedUntil);
    }

    /// @notice Lifts the pause: the owner always, the guardian only a stretch it opened. The real feed still applies.
    function resume() external {
        _onlyOwnerOrGuardian();
        if (msg.sender != owner && !pausedByGuardian) revert Unauthorized();
        if (isPaused() && pausedByGuardian) lastGuardianPauseEnd = block.timestamp;
        pausedUntil = 0;
        emit Resumed(msg.sender);
    }

    /// @notice Replaces the guardian. Only the owner.
    /// @param newGuardian New guardian; not the zero address.
    function setGuardian(address newGuardian) external {
        if (msg.sender != owner) revert Unauthorized();
        if (newGuardian == address(0)) revert InvalidAddress();
        emit GuardianChanged(guardian, newGuardian);
        guardian = newGuardian;
    }

    /// @notice Designates `newOwner`, who takes over by calling `acceptOwnership`. The zero address cancels a pending
    ///         transfer. Only the owner.
    /// @param newOwner Account designated to become the owner.
    function transferOwnership(address newOwner) external {
        if (msg.sender != owner) revert Unauthorized();
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    /// @notice Completes an ownership transfer; only the designated owner can call it.
    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert Unauthorized();
        emit OwnershipTransferred(owner, msg.sender);
        owner = msg.sender;
        pendingOwner = address(0);
    }

    /// @notice The real feed's latest round while not paused; while paused, answer 1 (down) at the current time.
    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        if (isPaused()) return (0, 1, block.timestamp, block.timestamp, 0);
        return feed.latestRoundData();
    }

    /// @notice Decimals of the real feed.
    function decimals() external view override returns (uint8) {
        return feed.decimals();
    }

    /// @notice Description of this feed.
    function description() external pure returns (string memory) {
        return "GBLIN sentinel over L2 Sequencer Uptime Status Feed";
    }
}
