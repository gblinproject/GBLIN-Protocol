// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @custom:website https://gblin.digital
 * @custom:mail info@gblin.digital
 */

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
    function balanceOf(address account) external view returns (uint256);
}

interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn; address tokenOut; uint24 fee; address recipient;
        uint256 amountIn; uint256 amountOutMinimum; uint160 sqrtPriceLimitX96;
    }
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);

    struct ExactInputParams {
        bytes path; address recipient; uint256 amountIn; uint256 amountOutMinimum;
    }
    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut);
}

interface IAggregatorMinMax {
    function aggregator() external view returns (address);
    function minAnswer() external view returns (int192);
    function maxAnswer() external view returns (int192);
}

contract GBLIN_GlobalBalancedLiquidityIndex is ERC20, ERC20Permit, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error SequencerDown(); error SlippageExceeded(); error Unauthorized();
    error CooldownActive(); error RebalanceNotNeeded(); error OracleDead();
    error SwapVolumeTooLow(); error InvalidAddress(); error WeightOutOfBounds();
    error AssetAlreadyExists(); error NoAssetProposed(); error TimelockActive();
    error InvalidIndex(); error InsufficientBalance(); error InvalidAmount();
    error TransferFailed(); error InvalidPath(); error NoExcessYield();
    error ParamOutOfBounds(); error InvalidBounds(); error CannotSwapSameToken();
    error ZeroOutput(); error DepositTooSmall(); error NotABasketAsset();

    struct Asset {
        address token; address oracle; uint24 poolFee; bool isStable;
        uint256 baseWeight; uint256 dynamicWeight;
        uint256 peakPrice; uint256 lastPeakUpdate;
        uint256 lastObservedPrice; uint256 ewmaVolBps; bool shielded;
        uint256 slowPeakPrice; uint256 slowLastPeakUpdate;
    }
    struct PendingAsset {
        address token; address oracle; uint24 poolFee; bool isStable;
        uint256 baseWeight; uint256 executeAfter;
    }

    address public swapRouter = 0x2626664c2603336E57B271c5C0b26F421741e481;
    address public constant WETH = 0x4200000000000000000000000000000000000006;
    address public constant cbBTC_TOKEN = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;
    address public constant USDC_TOKEN = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    uint256 constant BPS_DENOMINATOR = 10000;
    uint256 constant HARD_MAX_FEE_BPS = 500;
    uint256 constant HARD_MAX_MIN_DEPOSIT = 1 ether;
    uint256 constant HARD_MIN_ORACLE_TIMEOUT = 10 minutes;
    uint256 constant HARD_MAX_ORACLE_TIMEOUT = 30 days;
    uint256 constant HARD_MIN_CRASH_BPS = 300;
    uint256 constant HARD_MAX_CRASH_BPS = 9000;
    uint256 constant HARD_MAX_SLIPPAGE_BPS = 2000;
    uint256 constant HARD_MAX_INCENTIVE_BPS = 200;
    uint256 constant HARD_MAX_BASKET_SIZE = 50;
    uint256 constant MAX_ASSET_LISTING_DELAY = 7 days;
    uint256 constant MAX_NEW_ASSET_WEIGHT = 3000;

    uint256 public maxFeeBps = 50;
    uint256 public minDepositCap = 0.01 ether;
    uint256 public minOracleTimeout = 1 hours;
    uint256 public maxOracleTimeout = 7 days;
    uint256 public minCrashBps = 1500;
    uint256 public maxCrashBps = 5000;
    uint256 public maxSlippageBps = 1000;
    uint256 public maxIncentiveBps = 50;
    uint256 public maxBasketSize = 20;

    uint256 public founderFeeBps = 5;
    uint256 public stabilityFeeBps = 5;
    uint256 public minDeposit = 0;
    uint256 public oracleTimeout = 86400;
    uint256 public assetListingDelay = 48 hours;
    uint256 public baseCrashThresholdBps = 1500;
    uint256 public crashVolMultiplier = 5000;
    uint256 public recoveryBandBps = 800;
    uint256 public slashMultiplier = 2000;
    uint256 public peakDecayPerDayBps = 50;
    uint256 public slowPeakDecayPerDayBps = 5;
    uint256 public fullSlashDrawdownBps = 4500;
    uint256 public maxInternalSlippage = 550;
    uint256 public minSlippageBps = 50;
    uint256 public maxOracleDeviationBps = 2500;
    uint256 public keeperSplitBps = 5000;
    uint256 public keeperTargetBps = 500;
    uint256 public keeperTargetMin = 0.0001 ether;
    uint256 public keeperTargetMax = 0.05 ether;
    uint256 public incentiveBps = 5;
    uint256 public minBounty = 0.00005 ether;
    uint256 public maxBounty = 0.01 ether;
    uint256 public bountyInterval = 1 hours;
    uint256 public volumeWindow = 24 hours;
    uint256 public volumeRefEth = 10 ether;
    uint256 public diversifyOnBuyThreshold = 0.0005 ether;
    uint256 public volUpdateInterval = 1 hours;
    uint256 public lastVolRefresh;
    uint256 public sellCooldown = 20 seconds;

    address public WETH_ORACLE = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;
    address public SEQUENCER_FEED = 0xBCF85224fc0756B9Fa45aA7892530B47e10b6433;

    Asset[] public basket;
    PendingAsset public proposedAsset;
    address payable public founderWallet;
    address public owner;
    uint256 public stabilityFund;

    uint256 public windowStart;
    uint256 public windowVolume;
    uint256 public lastWindowVolume;

    mapping(address => uint256) public lastDepositTime;
    mapping(address => uint256) public lastRebalanceTime;
    uint256 public rebalanceCooldown = 0;
    uint256 public lastBountyTime;

    event Minted(address indexed user, uint256 ethValueIn, uint256 gblinOut);
    event InKindMinted(address indexed user, address indexed token, uint256 amountIn, uint256 gblinOut);
    event Burned(address indexed user, uint256 gblinIn);
    event Rebalanced(address indexed executor, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut, uint256 bounty);
    event CrashShieldActivated(address indexed token, uint256 drawdownBps, uint256 thresholdBps);
    event CrashShieldDeactivated(address indexed token);
    event YieldDistributed(uint256 amount);
    event AssetProposed(address indexed token, uint256 executeAfter);
    event AssetAdded(address indexed token, uint256 baseWeight);
    event AssetDelisted(address indexed token);
    event ParamUpdated(bytes32 what, uint256 a, uint256 b);
    event OracleUpdated(address indexed oldOracle, address indexed newOracle);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event FounderWalletUpdated(address indexed newWallet);

    modifier onlyOwner() { if (msg.sender != owner) revert Unauthorized(); _; }
    modifier onlyFounder() { if (msg.sender != founderWallet) revert Unauthorized(); _; }

    constructor(address payable _founder) ERC20("Global Balanced Liquidity Index", "GBLIN") ERC20Permit("GBLIN") {
        if (_founder == address(0)) revert InvalidAddress();
        founderWallet = _founder;
        owner = msg.sender;
        windowStart = block.timestamp;
        emit OwnershipTransferred(address(0), msg.sender);

        basket.push(Asset(cbBTC_TOKEN, 0x07DA0E54543a844a80ABE69c8A12F22B3aA59f9D, 500, false, 4500, 4500, 0, block.timestamp, 0, 0, false, 0, block.timestamp));
        basket.push(Asset(WETH, WETH_ORACLE, 0, false, 4500, 4500, 0, block.timestamp, 0, 0, false, 0, block.timestamp));
        basket.push(Asset(USDC_TOKEN, 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B, 500, true, 1000, 1000, 0, block.timestamp, 0, 0, false, 0, block.timestamp));
        refreshWeights();
    }

    function proposeAsset(address _token, address _oracle, uint24 _poolFee, bool _isStable, uint256 _baseWeight) external onlyOwner {
        if (_token == address(0) || _oracle == address(0)) revert InvalidAddress();
        if (_baseWeight == 0 || _baseWeight > MAX_NEW_ASSET_WEIGHT) revert WeightOutOfBounds();
        if (basket.length >= maxBasketSize) revert ParamOutOfBounds();
        for (uint i = 0; i < basket.length; i++) if (basket[i].token == _token) revert AssetAlreadyExists();
        if (_getOraclePrice(_oracle) == 0) revert OracleDead();
        _checkDecimals(_oracle);
        proposedAsset = PendingAsset(_token, _oracle, _poolFee, _isStable, _baseWeight, block.timestamp + assetListingDelay);
        emit AssetProposed(_token, proposedAsset.executeAfter);
    }

    function executeAssetAddition() external onlyOwner {
        if (proposedAsset.executeAfter == 0) revert NoAssetProposed();
        if (block.timestamp < proposedAsset.executeAfter) revert TimelockActive();
        if (_getOraclePrice(proposedAsset.oracle) == 0) revert OracleDead();
        uint256 p = _getOraclePrice(proposedAsset.oracle);
        basket.push(Asset(proposedAsset.token, proposedAsset.oracle, proposedAsset.poolFee, proposedAsset.isStable,
                          proposedAsset.baseWeight, proposedAsset.baseWeight, p, block.timestamp, p, 0, false, p, block.timestamp));
        emit AssetAdded(proposedAsset.token, proposedAsset.baseWeight);
        delete proposedAsset;
        refreshWeights();
    }

    function emergencyDelist(uint256 index) external onlyOwner {
        if (index >= basket.length) revert InvalidIndex();
        basket[index].baseWeight = 0;
        basket[index].dynamicWeight = 0;
        emit AssetDelisted(basket[index].token);
        refreshWeights();
    }

    function setFees(uint256 _founderBps, uint256 _stabilityBps) external onlyOwner {
        if (_founderBps + _stabilityBps > maxFeeBps) revert ParamOutOfBounds();
        founderFeeBps = _founderBps; stabilityFeeBps = _stabilityBps;
        emit ParamUpdated("fees", _founderBps, _stabilityBps);
    }
    function setMinDeposit(uint256 v) external onlyOwner {
        if (v > minDepositCap) revert ParamOutOfBounds();
        minDeposit = v; emit ParamUpdated("minDeposit", v, 0);
    }
    function setOracleTimeout(uint256 v) external onlyOwner {
        if (v < minOracleTimeout || v > maxOracleTimeout) revert ParamOutOfBounds();
        oracleTimeout = v; emit ParamUpdated("oracleTimeout", v, 0);
    }
    function setAssetListingDelay(uint256 secs) external onlyOwner {
        if (secs > MAX_ASSET_LISTING_DELAY) revert ParamOutOfBounds();
        assetListingDelay = secs; emit ParamUpdated("assetListingDelay", secs, 0);
    }
    function setCrashParams(uint256 baseBps, uint256 volMult, uint256 recovBps, uint256 slashMult) external onlyOwner {
        if (baseBps < minCrashBps || baseBps > maxCrashBps) revert ParamOutOfBounds();
        if (recovBps >= baseBps || slashMult > BPS_DENOMINATOR) revert ParamOutOfBounds();
        baseCrashThresholdBps = baseBps; crashVolMultiplier = volMult;
        recoveryBandBps = recovBps; slashMultiplier = slashMult;
        emit ParamUpdated("crashParams", baseBps, slashMult);
    }
    function setPeakDecay(uint256 bpsPerDay) external onlyOwner {
        if (bpsPerDay > 1000) revert ParamOutOfBounds();
        peakDecayPerDayBps = bpsPerDay; emit ParamUpdated("peakDecay", bpsPerDay, 0);
    }
    function setShieldCurve(uint256 slowDecay, uint256 fullSlashBps) external onlyOwner {
        if (slowDecay > peakDecayPerDayBps || fullSlashBps < minCrashBps || fullSlashBps > HARD_MAX_CRASH_BPS) revert ParamOutOfBounds();
        slowPeakDecayPerDayBps = slowDecay; fullSlashDrawdownBps = fullSlashBps;
        emit ParamUpdated("shieldCurve", slowDecay, fullSlashBps);
    }
    function setSlippage(uint256 bps) external onlyOwner {
        if (bps > maxSlippageBps || bps < minSlippageBps) revert ParamOutOfBounds();
        maxInternalSlippage = bps; emit ParamUpdated("slippage", bps, 0);
    }
    function setMinSlippage(uint256 bps) external onlyOwner {
        if (bps > maxInternalSlippage) revert ParamOutOfBounds();
        minSlippageBps = bps; emit ParamUpdated("minSlippage", bps, 0);
    }
    function setKeeperTarget(uint256 splitBps, uint256 bps, uint256 minT, uint256 maxT) external onlyOwner {
        if (splitBps > BPS_DENOMINATOR || minT > maxT) revert ParamOutOfBounds();
        keeperSplitBps = splitBps; keeperTargetBps = bps; keeperTargetMin = minT; keeperTargetMax = maxT;
        emit ParamUpdated("keeperTarget", splitBps, bps);
    }
    function setIncentive(uint256 _bps, uint256 _min, uint256 _max, uint256 _refEth) external onlyOwner {
        if (_bps > maxIncentiveBps || _min > _max) revert ParamOutOfBounds();
        incentiveBps = _bps; minBounty = _min; maxBounty = _max; volumeRefEth = _refEth;
        emit ParamUpdated("incentive", _bps, _refEth);
    }
    function setBountyInterval(uint256 secs) external onlyOwner {
        if (secs > 7 days) revert ParamOutOfBounds();
        bountyInterval = secs; emit ParamUpdated("bountyInterval", secs, 0);
    }
    function setDiversifyThreshold(uint256 v) external onlyOwner {
        diversifyOnBuyThreshold = v; emit ParamUpdated("diversifyThreshold", v, 0);
    }
    function setVolUpdateInterval(uint256 secs) external onlyOwner {
        if (secs < 5 minutes || secs > 1 days) revert ParamOutOfBounds();
        volUpdateInterval = secs; emit ParamUpdated("volUpdateInterval", secs, 0);
    }
    function setVolumeWindow(uint256 secs) external onlyOwner {
        if (secs < 1 hours || secs > 7 days) revert ParamOutOfBounds();
        volumeWindow = secs; emit ParamUpdated("volumeWindow", secs, 0);
    }
    function setRebalanceCooldown(uint256 secs) external onlyOwner {
        if (secs > 1 days) revert ParamOutOfBounds();
        rebalanceCooldown = secs; emit ParamUpdated("rebalanceCooldown", secs, 0);
    }
    function setSellCooldown(uint256 secs) external onlyOwner {
        if (secs > 1 hours) revert ParamOutOfBounds();
        sellCooldown = secs; emit ParamUpdated("sellCooldown", secs, 0);
    }

    function setFeeCap(uint256 v) external onlyOwner {
        if (v > HARD_MAX_FEE_BPS) revert ParamOutOfBounds();
        maxFeeBps = v; emit ParamUpdated("feeCap", v, 0);
    }
    function setCrashBounds(uint256 minB, uint256 maxB) external onlyOwner {
        if (minB < HARD_MIN_CRASH_BPS || maxB > HARD_MAX_CRASH_BPS || minB > maxB) revert ParamOutOfBounds();
        minCrashBps = minB; maxCrashBps = maxB; emit ParamUpdated("crashBounds", minB, maxB);
    }
    function setOracleBounds(uint256 minTo, uint256 maxTo) external onlyOwner {
        if (minTo < HARD_MIN_ORACLE_TIMEOUT || maxTo > HARD_MAX_ORACLE_TIMEOUT || minTo > maxTo) revert ParamOutOfBounds();
        minOracleTimeout = minTo; maxOracleTimeout = maxTo; emit ParamUpdated("oracleBounds", minTo, maxTo);
    }
    function setOpCaps(uint256 slip, uint256 incent, uint256 basketCap, uint256 minDep) external onlyOwner {
        if (slip > HARD_MAX_SLIPPAGE_BPS || incent > HARD_MAX_INCENTIVE_BPS
            || basketCap > HARD_MAX_BASKET_SIZE || basketCap < basket.length
            || minDep > HARD_MAX_MIN_DEPOSIT) revert ParamOutOfBounds();
        maxSlippageBps = slip; maxIncentiveBps = incent; maxBasketSize = basketCap; minDepositCap = minDep;
        emit ParamUpdated("opCaps", slip, incent);
    }
    function setOracleDeviation(uint256 bps) external onlyOwner {
        if (bps > BPS_DENOMINATOR) revert ParamOutOfBounds();
        maxOracleDeviationBps = bps; emit ParamUpdated("oracleDeviation", bps, 0);
    }
    function updateOracle(uint256 i, address newOracle) external onlyOwner {
        if (i >= basket.length || newOracle == address(0)) revert InvalidIndex();
        uint256 newP = _getOraclePrice(newOracle);
        if (newP == 0) revert OracleDead();
        _checkDecimals(newOracle);
        _checkDeviation(_getOraclePrice(basket[i].oracle), newP);
        emit OracleUpdated(basket[i].oracle, newOracle);
        basket[i].oracle = newOracle;
    }
    function updateWethOracle(address newOracle) external onlyOwner {
        uint256 newP = _getOraclePrice(newOracle);
        if (newOracle == address(0) || newP == 0) revert OracleDead();
        _checkDeviation(_getOraclePrice(WETH_ORACLE), newP);
        emit OracleUpdated(WETH_ORACLE, newOracle);
        WETH_ORACLE = newOracle;
    }
    function updateSequencerFeed(address feed) external onlyOwner {
        if (feed == address(0)) revert InvalidAddress();
        SEQUENCER_FEED = feed; emit ParamUpdated("sequencer", 0, 0);
    }
    function setSwapRouter(address r) external onlyOwner {
        if (r == address(0)) revert InvalidAddress();
        swapRouter = r; emit ParamUpdated("swapRouter", 0, 0);
    }
    function setAssetPoolFee(uint256 i, uint24 fee) external onlyOwner {
        if (i >= basket.length) revert InvalidIndex();
        basket[i].poolFee = fee; emit ParamUpdated("poolFee", i, fee);
    }
    function updateFounderWallet(address payable newWallet) external onlyFounder {
        if (newWallet == address(0)) revert InvalidAddress();
        founderWallet = newWallet; emit FounderWalletUpdated(newWallet);
    }

    function _calculateTotalEthValue(uint256 excludeWeth) internal view returns (uint256) {
        uint256 wethBal = IWETH(WETH).balanceOf(address(this));
        wethBal = wethBal > excludeWeth ? wethBal - excludeWeth : 0;
        uint256 total = wethBal > stabilityFund ? wethBal - stabilityFund : 0;
        for (uint i = 0; i < basket.length; i++) {
            if (basket[i].token != WETH) {
                uint256 bal = IERC20(basket[i].token).balanceOf(address(this));
                if (bal > 0) total += _convertToEth(basket[i], bal);
            }
        }
        return total;
    }

    function _calculateNAV(uint256 excludeWeth) internal view returns (uint256) {
        uint256 supply = _circulating();
        if (supply == 0) return 1 ether;
        return (_calculateTotalEthValue(excludeWeth) * 1 ether) / supply;
    }

    function quoteBuyGBLIN(uint256 ethAmount) external view returns (uint256 gblinOut, uint256 fFee, uint256 sFee) {
        return _quoteBuy(ethAmount, 0);
    }
    function quoteSellGBLIN(uint256 gblinAmount) external view returns (uint256 ethOut) {
        ethOut = (gblinAmount * _calculateNAV(0)) / 1 ether;
    }

    function _quoteBuy(uint256 ethValue, uint256 exWeth) internal view returns (uint256 out, uint256 fF, uint256 sF) {
        fF = (ethValue * founderFeeBps) / BPS_DENOMINATOR;
        sF = (ethValue * stabilityFeeBps) / BPS_DENOMINATOR;
        uint256 nav = _calculateNAV(exWeth);
        out = ((ethValue - fF - sF) * 1 ether) / nav;
    }

    function _convertToEth(Asset memory _a, uint256 _amt) internal view returns (uint256) {
        (uint256 pE, uint256 pA, uint8 d) = _prices(_a);
        if (pE == 0 || pA == 0) return 0;
        uint256 val = (_amt * pA) / pE;
        return d < 18 ? val * (10 ** (18 - d)) : val / (10 ** (d - 18));
    }
    function _convertEthToAsset(Asset memory _a, uint256 _ethAmt) internal view returns (uint256) {
        (uint256 pE, uint256 pA, uint8 d) = _prices(_a);
        if (pE == 0 || pA == 0) return 0;
        uint256 val = (_ethAmt * pE) / pA;
        return d < 18 ? val / (10 ** (18 - d)) : val * (10 ** (d - 18));
    }

    function buyGBLIN(uint256 minGblinOut) external payable nonReentrant {
        IWETH(WETH).deposit{value: msg.value}();
        _mintGBLIN(msg.value, minGblinOut, msg.sender);
    }

    function buyGBLINInKind(address token, uint256 amountIn, uint256 minGblinOut) external nonReentrant {
        _initMint();
        if (amountIn == 0) revert InvalidAmount();
        uint256 idx = type(uint256).max;
        for (uint i = 0; i < basket.length; i++) if (basket[i].token == token) { idx = i; break; }
        if (idx == type(uint256).max || basket[idx].dynamicWeight == 0) revert NotABasketAsset();

        uint256 ethValue = _convertToEth(basket[idx], amountIn);
        if (ethValue < minDeposit) revert DepositTooSmall();

        (uint256 gblinOut,,) = _quoteBuy(ethValue, 0);
        if (gblinOut == 0) revert ZeroOutput();
        if (gblinOut < minGblinOut) revert SlippageExceeded();

        uint256 balBefore = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(msg.sender, address(this), amountIn);
        if (IERC20(token).balanceOf(address(this)) - balBefore != amountIn) revert InvalidAmount();
        uint256 founderTok = (amountIn * founderFeeBps) / BPS_DENOMINATOR;
        if (founderTok > 0) IERC20(token).safeTransfer(founderWallet, founderTok);

        if (totalSupply() == 0) { _mint(address(this), 1000); if (gblinOut > 1000) gblinOut -= 1000; }
        _mint(msg.sender, gblinOut);

        _recordVolume(ethValue);
        lastDepositTime[msg.sender] = block.timestamp;
        emit InKindMinted(msg.sender, token, amountIn, gblinOut);
        emit YieldDistributed((ethValue * stabilityFeeBps) / BPS_DENOMINATOR);
    }

    function buyGBLINWithToken(bytes calldata path, uint256 amountIn, uint256 minWethOut, uint256 minGblinOut) external nonReentrant {
        if (path.length < 43) revert InvalidPath();
        address tokenIn; assembly { tokenIn := shr(96, calldataload(path.offset)) }
        uint256 wethAmount;
        if (tokenIn == WETH) {
            IERC20(WETH).safeTransferFrom(msg.sender, address(this), amountIn);
            wethAmount = amountIn;
        } else {
            address tokenOut; assembly { tokenOut := shr(96, calldataload(add(path.offset, sub(path.length, 20)))) }
            if (tokenOut != WETH) revert InvalidPath();
            IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
            IERC20(tokenIn).forceApprove(swapRouter, amountIn);
            uint256 wethBefore = IERC20(WETH).balanceOf(address(this));
            ISwapRouter(swapRouter).exactInput(ISwapRouter.ExactInputParams({
                path: path, recipient: address(this),
                amountIn: amountIn, amountOutMinimum: minWethOut
            }));
            wethAmount = IERC20(WETH).balanceOf(address(this)) - wethBefore;
            if (wethAmount < minWethOut) revert SlippageExceeded();
        }
        _mintGBLIN(wethAmount, minGblinOut, msg.sender);
    }

    function _mintGBLIN(uint256 wethAmount, uint256 minGblinOut, address receiver) internal {
        _initMint();
        if (wethAmount < minDeposit) revert DepositTooSmall();

        (uint256 gblinOut, uint256 fFee, uint256 sFee) = _quoteBuy(wethAmount, wethAmount);
        if (gblinOut == 0) revert ZeroOutput();
        if (gblinOut < minGblinOut) revert SlippageExceeded();

        _splitFee(sFee);
        if (totalSupply() == 0) { _mint(address(this), 1000); if (gblinOut > 1000) gblinOut -= 1000; }
        _mint(receiver, gblinOut);

        if (fFee > 0) {
            IWETH(WETH).withdraw(fFee);
            (bool ok, ) = founderWallet.call{value: fFee}("");
            if (!ok) { IWETH(WETH).deposit{value: fFee}(); stabilityFund += fFee; }
        }

        if (wethAmount >= diversifyOnBuyThreshold) {
            uint256 netEth = wethAmount - fFee - sFee;
            for (uint i = 0; i < basket.length; i++) {
                if (basket[i].token == WETH || basket[i].dynamicWeight == 0) continue;
                uint256 ethShare = (netEth * basket[i].dynamicWeight) / BPS_DENOMINATOR;
                if (ethShare > 0) {
                    uint256 minOut = _lessSlippage(_convertEthToAsset(basket[i], ethShare), basket[i].ewmaVolBps);
                    if (minOut > 0) {
                        try this.safeSwap(WETH, basket[i].token, basket[i].poolFee, ethShare, minOut) {} catch {}
                    }
                }
            }
        }

        _recordVolume(wethAmount);
        lastDepositTime[receiver] = block.timestamp;
        emit Minted(receiver, wethAmount, gblinOut);
    }

    function _splitFee(uint256 sFee) internal {
        uint256 target = _keeperTarget();
        uint256 toKeeper = 0;
        if (stabilityFund < target) {
            toKeeper = (sFee * keeperSplitBps) / BPS_DENOMINATOR;
            uint256 room = target - stabilityFund;
            if (toKeeper > room) toKeeper = room;
            stabilityFund += toKeeper;
        }
        uint256 distributed = sFee - toKeeper;
        if (distributed > 0) emit YieldDistributed(distributed);
    }

    function _keeperTarget() public view returns (uint256 t) {
        t = (lastWindowVolume * keeperTargetBps) / BPS_DENOMINATOR;
        if (t < keeperTargetMin) t = keeperTargetMin;
        if (t > keeperTargetMax) t = keeperTargetMax;
    }

    function _getPreBurnShares(uint256 gblinAmount, uint256 supply) internal view returns (uint256 wethShare, uint256[] memory assetShares) {
        uint256 wethBal = IWETH(WETH).balanceOf(address(this));
        uint256 availableWeth = wethBal > stabilityFund ? wethBal - stabilityFund : 0;
        wethShare = (availableWeth * gblinAmount) / supply;
        assetShares = new uint256[](basket.length);
        for (uint i = 0; i < basket.length; i++) {
            if (basket[i].token != WETH) {
                assetShares[i] = (IERC20(basket[i].token).balanceOf(address(this)) * gblinAmount) / supply;
            }
        }
    }

    function sellGBLIN(uint256 gblinAmount) external nonReentrant {
        (uint256 wethShare, uint256[] memory assetShares) = _initRedeem(gblinAmount);
        if (wethShare > 0) _sendEth(msg.sender, wethShare);
        for (uint i = 0; i < basket.length; i++) {
            if (basket[i].token != WETH && assetShares[i] > 0) {
                try IERC20(basket[i].token).transfer(msg.sender, assetShares[i]) returns (bool ok2) { ok2; } catch {}
            }
        }
        emit Burned(msg.sender, gblinAmount);
    }

    function sellGBLINForEth(uint256 gblinAmount, uint256 minEthOut) external nonReentrant {
        _checkSequencer();
        (uint256 wethShare, uint256[] memory assetShares) = _initRedeem(gblinAmount);
        uint256 totalWeth = wethShare;
        for (uint i = 0; i < basket.length; i++) {
            if (basket[i].token != WETH && assetShares[i] > 0) {
                uint256 expWeth = _convertToEth(basket[i], assetShares[i]);
                uint256 minOut = expWeth > 0 ? _lessSlippage(expWeth, basket[i].ewmaVolBps) : 0;
                try this.safeSwap(basket[i].token, WETH, basket[i].poolFee, assetShares[i], minOut) returns (uint256 w) {
                    totalWeth += w;
                } catch {}
            }
        }
        if (totalWeth < minEthOut) revert SlippageExceeded();
        _sendEth(msg.sender, totalWeth);
        emit Burned(msg.sender, gblinAmount);
    }

    function refreshWeights() public {
        uint256 totalSlashed = 0;
        uint256 healthyStable = 0;
        uint256 healthyRisk = 0;

        bool updateVol = block.timestamp >= lastVolRefresh + volUpdateInterval;

        for (uint i = 0; i < basket.length; i++) {
            Asset storage a = basket[i];
            a.dynamicWeight = a.baseWeight;
            if (a.baseWeight == 0) continue;

            uint256 cp = _getOraclePrice(a.oracle);
            if (cp == 0) { totalSlashed += a.baseWeight; a.dynamicWeight = 0; continue; }

            if (a.isStable) healthyStable++;
            else if (a.token != WETH) healthyRisk++;

            if (updateVol) {
                if (a.lastObservedPrice > 0) {
                    uint256 diff = cp > a.lastObservedPrice ? cp - a.lastObservedPrice : a.lastObservedPrice - cp;
                    uint256 instVolBps = (diff * BPS_DENOMINATOR) / a.lastObservedPrice;
                    a.ewmaVolBps = (instVolBps * 3 + a.ewmaVolBps * 7) / 10;
                }
                a.lastObservedPrice = cp;
            }

            uint256 daysPassed = (block.timestamp - a.lastPeakUpdate) / 86400;
            if (daysPassed > 0 && a.peakPrice > 0) {
                uint256 decay = (a.peakPrice * peakDecayPerDayBps * daysPassed) / BPS_DENOMINATOR;
                a.peakPrice = (decay < a.peakPrice) ? a.peakPrice - decay : cp;
                a.lastPeakUpdate = block.timestamp;
            }
            if (cp > a.peakPrice) { a.peakPrice = cp; a.lastPeakUpdate = block.timestamp; }

            uint256 sDays = (block.timestamp - a.slowLastPeakUpdate) / 86400;
            if (sDays > 0 && a.slowPeakPrice > 0) {
                uint256 sDecay = (a.slowPeakPrice * slowPeakDecayPerDayBps * sDays) / BPS_DENOMINATOR;
                a.slowPeakPrice = (sDecay < a.slowPeakPrice) ? a.slowPeakPrice - sDecay : cp;
                a.slowLastPeakUpdate = block.timestamp;
            }
            if (cp > a.slowPeakPrice) { a.slowPeakPrice = cp; a.slowLastPeakUpdate = block.timestamp; }

            uint256 ddFast = a.peakPrice > cp ? ((a.peakPrice - cp) * BPS_DENOMINATOR) / a.peakPrice : 0;
            uint256 ddSlow = a.slowPeakPrice > cp ? ((a.slowPeakPrice - cp) * BPS_DENOMINATOR) / a.slowPeakPrice : 0;
            uint256 drawdown = ddFast > ddSlow ? ddFast : ddSlow;

            uint256 effThreshold = baseCrashThresholdBps + (a.ewmaVolBps * crashVolMultiplier) / BPS_DENOMINATOR;
            if (effThreshold < minCrashBps) effThreshold = minCrashBps;
            if (effThreshold > maxCrashBps) effThreshold = maxCrashBps;

            if (!a.shielded && drawdown > effThreshold) {
                a.shielded = true;
                emit CrashShieldActivated(a.token, drawdown, effThreshold);
            } else if (a.shielded && drawdown < recoveryBandBps) {
                a.shielded = false;
                emit CrashShieldDeactivated(a.token);
            }

            if (a.shielded) {
                uint256 sev;
                if (drawdown >= fullSlashDrawdownBps) sev = BPS_DENOMINATOR;
                else if (drawdown > effThreshold && fullSlashDrawdownBps > effThreshold)
                    sev = ((drawdown - effThreshold) * BPS_DENOMINATOR) / (fullSlashDrawdownBps - effThreshold);
                uint256 keepBps = BPS_DENOMINATOR - (sev * (BPS_DENOMINATOR - slashMultiplier)) / BPS_DENOMINATOR;
                uint256 newWeight = (a.baseWeight * keepBps) / BPS_DENOMINATOR;
                totalSlashed += (a.baseWeight - newWeight);
                a.dynamicWeight = newWeight;
            }
        }

        if (totalSlashed > 0) {
            if (healthyStable > 0) {
                uint256 extra = totalSlashed / healthyStable;
                for (uint i = 0; i < basket.length; i++) if (basket[i].isStable && basket[i].dynamicWeight > 0) basket[i].dynamicWeight += extra;
            } else if (healthyRisk > 0) {
                uint256 extra = totalSlashed / healthyRisk;
                for (uint i = 0; i < basket.length; i++) if (!basket[i].isStable && basket[i].token != WETH && basket[i].dynamicWeight > 0) basket[i].dynamicWeight += extra;
            }
        }
        if (updateVol) lastVolRefresh = block.timestamp;
    }

    function _getOraclePrice(address _oracle) internal view returns (uint256) {
        try AggregatorV3Interface(_oracle).latestRoundData() returns (uint80, int256 price, uint256, uint256 updatedAt, uint80) {
            if (block.timestamp - updatedAt > oracleTimeout || price <= 0) return 0;
            if (!_withinBounds(_oracle, price)) return 0;
            return uint256(price);
        } catch { return 0; }
    }

    function _withinBounds(address _oracle, int256 price) internal view returns (bool) {
        try IAggregatorMinMax(_oracle).aggregator() returns (address agg) {
            try IAggregatorMinMax(agg).minAnswer() returns (int192 mn) {
                try IAggregatorMinMax(agg).maxAnswer() returns (int192 mx) {
                    return price > int256(mn) && price < int256(mx);
                } catch { return true; }
            } catch { return true; }
        } catch { return true; }
    }

    function _checkSequencer() internal view {
        (, int256 answer, uint256 startedAt, , ) = AggregatorV3Interface(SEQUENCER_FEED).latestRoundData();
        if (answer == 1 || (block.timestamp - startedAt <= 3600)) revert SequencerDown();
    }

    function incentivizedRebalance(uint256 assetIndex, bool isWethToAsset, uint256 amountToSwap) external nonReentrant {
        _checkSequencer();
        if (_getOraclePrice(WETH_ORACLE) == 0) revert OracleDead();
        if (assetIndex >= basket.length) revert InvalidIndex();
        if (rebalanceCooldown > 0 && block.timestamp < lastRebalanceTime[msg.sender] + rebalanceCooldown) revert CooldownActive();
        Asset memory a = basket[assetIndex];
        if (a.token == WETH) revert CannotSwapSameToken();
        if (_getOraclePrice(a.oracle) == 0) revert OracleDead();

        uint256 minSwapRequired = IWETH(WETH).balanceOf(address(this)) / 100;
        if (minSwapRequired < 0.01 ether) minSwapRequired = 0.01 ether;

        refreshWeights();
        uint256 targetEth = (_calculateTotalEthValue(0) * basket[assetIndex].dynamicWeight) / BPS_DENOMINATOR;
        uint256 currentEth = _convertToEth(a, IERC20(a.token).balanceOf(address(this)));
        uint256 out;
        uint256 rebalancedEth;

        if (isWethToAsset) {
            if (currentEth >= targetEth) revert RebalanceNotNeeded();
            uint256 maxEth = targetEth - currentEth;
            uint256 avail = IWETH(WETH).balanceOf(address(this));
            avail = avail > stabilityFund ? avail - stabilityFund : 0;
            if (maxEth > avail) maxEth = avail;
            if (amountToSwap > maxEth) amountToSwap = maxEth;

            if (amountToSwap < minSwapRequired) revert SwapVolumeTooLow();

            uint256 minOut = _lessSlippage(_convertEthToAsset(a, amountToSwap), a.ewmaVolBps);
            out = _swap(WETH, a.token, a.poolFee, amountToSwap, minOut);
            rebalancedEth = amountToSwap;
        } else {
            if (currentEth <= targetEth) revert RebalanceNotNeeded();
            uint256 maxAsset = _convertEthToAsset(a, currentEth - targetEth);
            if (amountToSwap > maxAsset) amountToSwap = maxAsset;
            if (amountToSwap == 0) revert RebalanceNotNeeded();

            rebalancedEth = _convertToEth(a, amountToSwap);
            if (rebalancedEth < minSwapRequired) revert SwapVolumeTooLow();

            uint256 minOut = _lessSlippage(rebalancedEth, a.ewmaVolBps);
            out = _swap(a.token, WETH, a.poolFee, amountToSwap, minOut);
        }

        lastRebalanceTime[msg.sender] = block.timestamp;

        uint256 bounty = 0;
        if (block.timestamp >= lastBountyTime + bountyInterval) {
            uint256 due = _bounty(rebalancedEth);
            if (due > 0 && due <= stabilityFund) {
                bounty = due;
                lastBountyTime = block.timestamp;
                stabilityFund -= bounty;
                _sendEth(msg.sender, bounty);
            }
        }
        emit Rebalanced(msg.sender, isWethToAsset ? WETH : a.token, isWethToAsset ? a.token : WETH, amountToSwap, out, bounty);
    }

    function _bounty(uint256 rebalancedEth) internal view returns (uint256 b) {
        uint256 boost = _volumeBoost();
        uint256 effBps = incentiveBps + (incentiveBps * boost) / BPS_DENOMINATOR;
        b = (rebalancedEth * effBps) / BPS_DENOMINATOR;
        if (b < minBounty) b = minBounty;
        if (b > maxBounty) b = maxBounty;
    }

    function _volumeBoost() internal view returns (uint256) {
        uint256 v = lastWindowVolume;
        if (volumeRefEth == 0) return 0;
        if (v >= volumeRefEth) return BPS_DENOMINATOR;
        return (v * BPS_DENOMINATOR) / volumeRefEth;
    }

    function _recordVolume(uint256 ethAmount) internal {
        if (block.timestamp >= windowStart + volumeWindow) {
            lastWindowVolume = windowVolume;
            windowVolume = 0;
            windowStart = block.timestamp;
        }
        windowVolume += ethAmount;
    }

    function _requireFreshOracles() internal view {
        if (_getOraclePrice(WETH_ORACLE) == 0) revert OracleDead();
        for (uint i = 0; i < basket.length; i++) {
            if (basket[i].baseWeight > 0 && _getOraclePrice(basket[i].oracle) == 0) revert OracleDead();
        }
    }

    function _swap(address tIn, address tOut, uint24 fee, uint256 amtIn, uint256 mOut) internal returns (uint256) {
        IERC20(tIn).forceApprove(swapRouter, amtIn);
        return ISwapRouter(swapRouter).exactInputSingle(ISwapRouter.ExactInputSingleParams({
            tokenIn: tIn, tokenOut: tOut, fee: fee, recipient: address(this),
            amountIn: amtIn, amountOutMinimum: mOut, sqrtPriceLimitX96: 0
        }));
    }

    function _lessSlippage(uint256 v, uint256 volBps) internal view returns (uint256) {
        uint256 slip = minSlippageBps + volBps;
        if (slip > maxInternalSlippage) slip = maxInternalSlippage;
        return v - (v * slip) / BPS_DENOMINATOR;
    }

    function _checkDecimals(address oracle) internal view {
        if (AggregatorV3Interface(oracle).decimals() != AggregatorV3Interface(WETH_ORACLE).decimals()) revert ParamOutOfBounds();
    }

    function _checkDeviation(uint256 oldP, uint256 newP) internal view {
        if (oldP == 0) return;
        uint256 diff = newP > oldP ? newP - oldP : oldP - newP;
        if ((diff * BPS_DENOMINATOR) / oldP > maxOracleDeviationBps) revert ParamOutOfBounds();
    }

    function _circulating() internal view returns (uint256) {
        return totalSupply() - balanceOf(address(this));
    }
    function _initMint() internal view {
        _checkSequencer();
        _requireFreshOracles();
    }
    function _sendEth(address to, uint256 amt) internal {
        IWETH(WETH).withdraw(amt);
        (bool ok, ) = payable(to).call{value: amt}("");
        if (!ok) revert TransferFailed();
    }
    function _prices(Asset memory _a) internal view returns (uint256 pE, uint256 pA, uint8 d) {
        pE = _getOraclePrice(WETH_ORACLE); pA = _getOraclePrice(_a.oracle);
        d = IERC20Metadata(_a.token).decimals();
    }
    function _initRedeem(uint256 gblinAmount) internal returns (uint256 wethShare, uint256[] memory assetShares) {
        if (block.timestamp < lastDepositTime[msg.sender] + sellCooldown) revert CooldownActive();
        uint256 supply = _circulating();
        if (supply == 0 || gblinAmount == 0 || gblinAmount > balanceOf(msg.sender)) revert InvalidAmount();
        (wethShare, assetShares) = _getPreBurnShares(gblinAmount, supply);
        _burn(msg.sender, gblinAmount);
    }

    function safeSwap(address tIn, address tOut, uint24 fee, uint256 amtIn, uint256 mOut) public returns (uint256) {
        if (msg.sender != address(this)) revert Unauthorized();
        return _swap(tIn, tOut, fee, amtIn, mOut);
    }

    function basketLength() external view returns (uint256) { return basket.length; }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidAddress();
        address old = owner; owner = newOwner;
        emit OwnershipTransferred(old, newOwner);
    }

    function wrapStrayEth() external nonReentrant {
        uint256 bal = address(this).balance;
        if (bal > 0) IWETH(WETH).deposit{value: bal}();
    }

    receive() external payable {}
}
