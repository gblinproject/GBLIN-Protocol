// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title GBLIN V5 - Global Balanced Liquidity Index
 * @dev Ultra-Optimized for Base Mainnet (Deduplicated logic to bypass Spurious Dragon limit).
 * Features: Anti-Dilution NAV Snapshotting, Denominator Integrity, Institutional In-Kind Facility, 
 * Timelocked Governance, Crash Shield, and Dynamic Slippage Control.
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
        bytes path; address recipient; uint256 deadline; uint256 amountIn; uint256 amountOutMinimum;
    }
    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut);
}

contract GBLIN_GlobalBalancedLiquidityIndex is ERC20, ERC20Permit, ReentrancyGuard {
    
    // --- CUSTOM ERRORS ---
    error SequencerDown(); error DepositTooSmall(); error SlippageExceeded();
    error Unauthorized(); error CooldownActive(); error RebalanceNotNeeded();
    error OracleDead(); error SwapVolumeTooLow(); error InvalidAddress();
    error WeightOutOfBounds(); error AssetAlreadyExists(); error NoAssetProposed();
    error TimelockActive(); error InvalidIndex(); error InsufficientBalance();
    error InvalidAmount(); error TransferFailed(); error NoWethObtained();
    error InvalidPath(); error TimeNotPassed(); error NoExcessYield();
    error MaxSlippageExceeded(); error InvalidBounds(); error CannotSwapSameToken();

    // --- STRUCTS ---
    struct Asset {
        address token; address oracle; uint24 poolFee; bool isStable;
        uint256 baseWeight; uint256 dynamicWeight; uint256 peakPrice; uint256 lastPeakUpdate;   
    }
    struct PendingAsset {
        address token; address oracle; uint24 poolFee; bool isStable; 
        uint256 baseWeight; uint256 executeAfter;
    }

    // --- CORE ADDRESSES ---
    address public constant UNISWAP_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481;
    address public constant WETH = 0x4200000000000000000000000000000000000006;
    address public constant cbBTC_TOKEN = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;
    address public constant USDC_TOKEN = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address public WETH_ORACLE = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;
    address public SEQUENCER_FEED = 0xBCF85224fc0756B9Fa45aA7892530B47e10b6433;

    // --- STATE VARIABLES ---
    Asset[] public basket;
    PendingAsset public proposedAsset;
    
    address payable public founderWallet;
    address public owner; 
    uint256 public stabilityFund;
    
    uint256 public constant FOUNDER_FEE_BPS = 5;
    uint256 public constant STABILITY_FEE_BPS = 5;
    uint256 public constant BPS_DENOMINATOR = 10000;
    uint256 public constant MIN_DEPOSIT = 0.0005 ether;
    uint256 public constant ORACLE_TIMEOUT = 86400; 
    uint256 public constant TIMELOCK_DURATION = 48 hours;
    uint256 public constant MAX_NEW_ASSET_WEIGHT = 3000; 
    uint256 public constant CRASH_THRESHOLD_BPS = 2000; 
    uint256 public constant SLASH_MULTIPLIER = 2000;    
    uint256 public constant PEAK_DECAY_PER_DAY = 50; 
    
    uint256 public maxInternalSlippage = 200;

    uint256 public constant YIELD_INTERVAL = 7 days;
    uint256 public lastYieldDistribution;
    uint256 public reserveFloor = 0.05 ether;
    uint256 public reserveCeiling = 2 ether;

    mapping(address => uint256) public lastDepositTime;

    // --- EVENTS ---
    event Minted(address indexed user, uint256 ethIn, uint256 gblinOut);
    event InKindMinted(address indexed user, uint256 gblinOut);
    event Burned(address indexed user, uint256 gblinIn);
    event InKindRedeemed(address indexed user, uint256 gblinIn);
    event Rebalanced(address indexed executor, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);
    event CrashShieldActivated(address indexed token, uint256 newDynamicWeight);
    event CrashShieldDeactivated(address indexed token, uint256 restoredWeight);
    event YieldDistributed(uint256 amount);
    event AssetProposed(address indexed token, uint256 executeAfter);
    event AssetAdded(address indexed token, uint256 baseWeight);
    event AssetDelisted(address indexed token);
    event OracleUpdated(address indexed oldOracle, address indexed newOracle);
    event ReserveBoundsUpdated(uint256 newFloor, uint256 newCeiling);
    event MaxSlippageUpdated(uint256 oldSlippage, uint256 newSlippage);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event ProtocolLockedForever();

    modifier onlyOwner() { if (msg.sender != owner) revert Unauthorized(); _; }
    modifier onlyFounder() { if (msg.sender != founderWallet) revert Unauthorized(); _; }

    constructor(address payable _founder) ERC20("Global Balanced Liquidity Index", "GBLIN") ERC20Permit("GBLIN") {
        founderWallet = _founder;
        owner = msg.sender;
        lastYieldDistribution = block.timestamp;
        emit OwnershipTransferred(address(0), msg.sender);

        basket.push(Asset(cbBTC_TOKEN, 0x07DA0E54543a844a80ABE69c8A12F22B3aA59f9D, 500, false, 4500, 4500, 0, block.timestamp)); 
        basket.push(Asset(WETH, WETH_ORACLE, 0, false, 4500, 4500, 0, block.timestamp)); 
        basket.push(Asset(USDC_TOKEN, 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B, 500, true, 1000, 1000, 0, block.timestamp));
        refreshWeights();
    }

    // ==========================================
    // 1. INSTITUTIONAL GOVERNANCE
    // ==========================================
    function proposeAsset(address _token, address _oracle, uint24 _poolFee, bool _isStable, uint256 _baseWeight) external onlyOwner {
        if (_token == address(0) || _oracle == address(0)) revert InvalidAddress();
        if (_baseWeight == 0 || _baseWeight > MAX_NEW_ASSET_WEIGHT) revert WeightOutOfBounds();
        
        for(uint i = 0; i < basket.length; i++) {
            if (basket[i].token == _token) revert AssetAlreadyExists();
        }
        if (_getOraclePrice(_oracle) == 0) revert OracleDead();

        proposedAsset = PendingAsset({
            token: _token, oracle: _oracle, poolFee: _poolFee, isStable: _isStable,
            baseWeight: _baseWeight, executeAfter: block.timestamp + TIMELOCK_DURATION
        });
        emit AssetProposed(_token, proposedAsset.executeAfter);
    }

    function executeAssetAddition() external onlyOwner {
        if (proposedAsset.executeAfter == 0) revert NoAssetProposed();
        if (block.timestamp < proposedAsset.executeAfter) revert TimelockActive();
        if (_getOraclePrice(proposedAsset.oracle) == 0) revert OracleDead();

        basket.push(Asset({
            token: proposedAsset.token, oracle: proposedAsset.oracle, poolFee: proposedAsset.poolFee,
            isStable: proposedAsset.isStable, baseWeight: proposedAsset.baseWeight,
            dynamicWeight: proposedAsset.baseWeight, peakPrice: _getOraclePrice(proposedAsset.oracle), lastPeakUpdate: block.timestamp
        }));

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

    // ==========================================
    // 2. INSTITUTIONAL IN-KIND FACILITY 
    // ==========================================
    function quoteMintInKind(uint256 gblinTarget) public view returns (uint256[] memory requiredAssets) {
        uint256 nav = _calculateNAV(0);
        uint256 totalEthNeeded = (gblinTarget * nav) / 1 ether;
        requiredAssets = new uint256[](basket.length);
        for (uint i = 0; i < basket.length; i++) {
            if (basket[i].dynamicWeight > 0) {
                uint256 assetEthValue = (totalEthNeeded * basket[i].dynamicWeight) / BPS_DENOMINATOR;
                requiredAssets[i] = _convertEthToAsset(basket[i], assetEthValue);
            }
        }
    }

    function mintInKind(uint256 gblinTarget) external nonReentrant {
        _checkSequencer();
        uint256[] memory amounts = quoteMintInKind(gblinTarget);
        
        for (uint i = 0; i < basket.length; i++) {
            if (amounts[i] > 0) IERC20(basket[i].token).transferFrom(msg.sender, address(this), amounts[i]);
        }

        uint256 fFee = (gblinTarget * FOUNDER_FEE_BPS) / BPS_DENOMINATOR;
        uint256 sFee = (gblinTarget * STABILITY_FEE_BPS) / BPS_DENOMINATOR;
        uint256 netMint = gblinTarget - fFee - sFee;

        _mint(msg.sender, netMint);
        if (fFee > 0) _mint(founderWallet, fFee);
        if (sFee > 0) {
            _mint(address(this), sFee);
            _burn(address(this), sFee); 
        }

        lastDepositTime[msg.sender] = block.timestamp;
        emit InKindMinted(msg.sender, netMint);
    }

    function redeemInKind(uint256 gblinAmount) external nonReentrant {
        _checkSequencer();
        if (block.timestamp < lastDepositTime[msg.sender] + 2 minutes) revert CooldownActive();
        
        uint256 supply = totalSupply() - balanceOf(address(this));
        if (gblinAmount == 0 || gblinAmount > balanceOf(msg.sender)) revert InvalidAmount();

        (uint256 wethShare, uint256[] memory assetShares) = _getPreBurnShares(gblinAmount, supply);

        _burn(msg.sender, gblinAmount);

        for (uint i = 0; i < basket.length; i++) {
            if (assetShares[i] > 0) IERC20(basket[i].token).transfer(msg.sender, assetShares[i]);
        }
        if (wethShare > 0) IERC20(WETH).transfer(msg.sender, wethShare); // For WETH in-kind if needed directly

        emit InKindRedeemed(msg.sender, gblinAmount);
    }

    // ==========================================
    // 3. STANDARD RETAIL OPERATIONS 
    // ==========================================
    function _calculateTotalEthValue(uint256 excludeWeth) internal view returns (uint256) {
        uint256 wethBal = IWETH(WETH).balanceOf(address(this));
        wethBal = wethBal > excludeWeth ? wethBal - excludeWeth : 0;
        uint256 totalEthVal = wethBal > stabilityFund ? wethBal - stabilityFund : 0;
        
        for (uint i = 0; i < basket.length; i++) {
            if (basket[i].token != WETH && basket[i].dynamicWeight > 0) {
                uint256 bal = IERC20(basket[i].token).balanceOf(address(this));
                if (bal > 0) totalEthVal += _convertToEth(basket[i], bal);
            }
        }
        return totalEthVal;
    }

    function _calculateNAV(uint256 excludeWeth) internal view returns (uint256) {
        uint256 supply = totalSupply() - balanceOf(address(this));
        if (supply == 0) return 1 ether;
        return (_calculateTotalEthValue(excludeWeth) * 1 ether) / supply;
    }

    function quoteBuyGBLIN(uint256 ethAmount) public view returns (uint256 gblinOut, uint256 founderFee, uint256 stabFee) {
        return _quoteBuy(ethAmount, 0);
    }

    function quoteSellGBLIN(uint256 gblinAmount) public view returns (uint256 ethOut) {
        uint256 nav = _calculateNAV(0);
        ethOut = (gblinAmount * nav) / 1 ether;
    }

    function _quoteBuy(uint256 ethAmt, uint256 exWeth) internal view returns (uint256 out, uint256 fF, uint256 sF) {
        if (ethAmt < MIN_DEPOSIT) return (0, 0, 0);
        fF = (ethAmt * FOUNDER_FEE_BPS) / BPS_DENOMINATOR;
        sF = (ethAmt * STABILITY_FEE_BPS) / BPS_DENOMINATOR;
        uint256 nav = _calculateNAV(exWeth);
        out = ((ethAmt - fF - sF) * 1 ether) / nav;
    }

    function _mintGBLIN(uint256 wethAmount, uint256 minGblinOut, address receiver) internal {
        _checkSequencer();
        if (wethAmount < MIN_DEPOSIT) revert DepositTooSmall();
        
        (uint256 gblinOut, uint256 fFee, uint256 sFee) = _quoteBuy(wethAmount, wethAmount);
        if (gblinOut < minGblinOut) revert SlippageExceeded();

        stabilityFund += sFee;
        if (totalSupply() == 0) { _mint(address(this), 1000); gblinOut -= 1000; }
        _mint(receiver, gblinOut);
        
        if (fFee > 0) {
            IWETH(WETH).withdraw(fFee);
            (bool success, ) = founderWallet.call{value: fFee}("");
            if (!success) { IWETH(WETH).deposit{value: fFee}(); stabilityFund += fFee; }
        }

        uint256 netEth = wethAmount - fFee - sFee;
        for (uint i = 0; i < basket.length; i++) {
            if (basket[i].token == WETH || basket[i].dynamicWeight == 0) continue;
            uint256 ethShare = (netEth * basket[i].dynamicWeight) / BPS_DENOMINATOR;
            if (ethShare > 0) {
                uint256 minOut = _convertEthToAsset(basket[i], ethShare);
                minOut -= (minOut * maxInternalSlippage) / BPS_DENOMINATOR;
                if(minOut > 0) {
                    try this.safeSwap(WETH, basket[i].token, basket[i].poolFee, ethShare, minOut) {} catch {}
                }
            }
        }
        lastDepositTime[receiver] = block.timestamp;
        emit Minted(receiver, wethAmount, gblinOut);
        _autoDistributeYield();
    }

    function buyGBLIN(uint256 minGblinOut) external payable nonReentrant {
        IWETH(WETH).deposit{value: msg.value}();
        _mintGBLIN(msg.value, minGblinOut, msg.sender);
    }

    function buyGBLINWithToken(bytes calldata path, uint256 amountIn, uint256 minWethOut, uint256 minGblinOut) external nonReentrant {
        if(path.length < 43) revert InvalidPath();
        address tokenIn; assembly { tokenIn := shr(96, calldataload(path.offset)) }
        uint256 wethAmount;

        if (tokenIn == WETH) {
            IERC20(WETH).transferFrom(msg.sender, address(this), amountIn);
            wethAmount = amountIn;
        } else {
            IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
            IERC20(tokenIn).approve(UNISWAP_ROUTER, amountIn);
            uint256 wethBefore = IERC20(WETH).balanceOf(address(this));
            ISwapRouter(UNISWAP_ROUTER).exactInput(ISwapRouter.ExactInputParams({
                path: path, recipient: address(this), deadline: block.timestamp,
                amountIn: amountIn, amountOutMinimum: minWethOut
            }));
            wethAmount = IERC20(WETH).balanceOf(address(this)) - wethBefore;
            if(wethAmount < minWethOut) revert SlippageExceeded();
        }
        _mintGBLIN(wethAmount, minGblinOut, msg.sender);
    }

    // --- V5.1 DEDUPLICATION FIX: Shared Burn Logic ---
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
        _checkSequencer();
        if (block.timestamp < lastDepositTime[msg.sender] + 2 minutes) revert CooldownActive();
        uint256 supply = totalSupply() - balanceOf(address(this));
        if (supply == 0 || gblinAmount == 0 || gblinAmount > balanceOf(msg.sender)) revert InvalidAmount();

        (uint256 wethShare, uint256[] memory assetShares) = _getPreBurnShares(gblinAmount, supply);

        _burn(msg.sender, gblinAmount);

        if (wethShare > 0) {
            IWETH(WETH).withdraw(wethShare);
            (bool success, ) = payable(msg.sender).call{value: wethShare}("");
            if (!success) revert TransferFailed();
        }
        for (uint i = 0; i < basket.length; i++) {
            if (basket[i].token != WETH && assetShares[i] > 0) IERC20(basket[i].token).transfer(msg.sender, assetShares[i]);
        }
        emit Burned(msg.sender, gblinAmount);
        _autoDistributeYield();
    }

    function sellGBLINForEth(uint256 gblinAmount, uint256 minEthOut) external nonReentrant {
        _checkSequencer();
        if (block.timestamp < lastDepositTime[msg.sender] + 2 minutes) revert CooldownActive();
        uint256 supply = totalSupply() - balanceOf(address(this));
        if (supply == 0 || gblinAmount == 0 || gblinAmount > balanceOf(msg.sender)) revert InvalidAmount();

        (uint256 wethShare, uint256[] memory assetShares) = _getPreBurnShares(gblinAmount, supply);

        _burn(msg.sender, gblinAmount);
        uint256 totalWethObtained = wethShare;

        for (uint i = 0; i < basket.length; i++) {
            if (basket[i].token != WETH && assetShares[i] > 0) {
                uint256 expectedWeth = _convertToEth(basket[i], assetShares[i]);
                uint256 minWethOut = expectedWeth > 0 ? expectedWeth - ((expectedWeth * maxInternalSlippage) / BPS_DENOMINATOR) : 0;
                totalWethObtained += this.safeSwap(basket[i].token, WETH, basket[i].poolFee, assetShares[i], minWethOut);
            }
        }

        if (totalWethObtained < minEthOut) revert SlippageExceeded();
        IWETH(WETH).withdraw(totalWethObtained);
        (bool success, ) = payable(msg.sender).call{value: totalWethObtained}("");
        if (!success) revert TransferFailed();

        emit Burned(msg.sender, gblinAmount);
        _autoDistributeYield();
    }

    function sellGBLINForToken(uint256 gblinAmount, address targetToken, uint24 wethToTargetFee, uint256 minTokenOut) external nonReentrant {
        _checkSequencer();
        if (block.timestamp < lastDepositTime[msg.sender] + 2 minutes) revert CooldownActive();
        uint256 supply = totalSupply() - balanceOf(address(this));
        if (supply == 0 || gblinAmount == 0 || gblinAmount > balanceOf(msg.sender)) revert InvalidAmount();

        (uint256 wethShare, uint256[] memory assetShares) = _getPreBurnShares(gblinAmount, supply);

        _burn(msg.sender, gblinAmount);
        uint256 totalWethObtained = wethShare;

        for (uint i = 0; i < basket.length; i++) {
            if (basket[i].token != WETH && assetShares[i] > 0) {
                uint256 expectedWeth = _convertToEth(basket[i], assetShares[i]);
                uint256 minWethOut = expectedWeth > 0 ? expectedWeth - ((expectedWeth * maxInternalSlippage) / BPS_DENOMINATOR) : 0;
                totalWethObtained += this.safeSwap(basket[i].token, WETH, basket[i].poolFee, assetShares[i], minWethOut);
            }
        }

        if (totalWethObtained == 0) revert NoWethObtained();
        
        if (targetToken == WETH) {
            if (totalWethObtained < minTokenOut) revert SlippageExceeded();
            IERC20(WETH).transfer(msg.sender, totalWethObtained);
        } else {
            IERC20(WETH).approve(UNISWAP_ROUTER, totalWethObtained);
            ISwapRouter(UNISWAP_ROUTER).exactInputSingle(ISwapRouter.ExactInputSingleParams({
                tokenIn: WETH, tokenOut: targetToken, fee: wethToTargetFee, recipient: msg.sender,
                amountIn: totalWethObtained, amountOutMinimum: minTokenOut, sqrtPriceLimitX96: 0
            }));
        }

        emit Burned(msg.sender, gblinAmount);
        _autoDistributeYield();
    }

    // ==========================================
    // 4. CORE MATH & REBALANCING
    // ==========================================
    function refreshWeights() public {
        uint256 totalSlashedWeight = 0;
        uint256 healthyStableCount = 0;
        uint256 healthyRiskCount = 0;

        for (uint i = 0; i < basket.length; i++) basket[i].dynamicWeight = basket[i].baseWeight;

        for (uint i = 0; i < basket.length; i++) {
            Asset storage a = basket[i];
            if (a.baseWeight == 0) continue;

            uint256 currentPrice = _getOraclePrice(a.oracle);
            if (currentPrice == 0) {
                totalSlashedWeight += a.baseWeight;
                a.dynamicWeight = 0;
                continue;
            }

            if (a.isStable) healthyStableCount++;
            else if (a.token != WETH) healthyRiskCount++;

            uint256 daysPassed = (block.timestamp - a.lastPeakUpdate) / 86400;
            if (daysPassed > 0 && a.peakPrice > 0) {
                uint256 decay = (a.peakPrice * PEAK_DECAY_PER_DAY * daysPassed) / BPS_DENOMINATOR;
                a.peakPrice = (decay < a.peakPrice) ? a.peakPrice - decay : currentPrice;
                a.lastPeakUpdate = block.timestamp;
            }

            if (currentPrice > a.peakPrice) {
                a.peakPrice = currentPrice;
                a.lastPeakUpdate = block.timestamp;
            }

            uint256 drawdown = a.peakPrice > 0 ? ((a.peakPrice - currentPrice) * BPS_DENOMINATOR) / a.peakPrice : 0;
            
            if (drawdown > CRASH_THRESHOLD_BPS) {
                uint256 newWeight = (a.baseWeight * SLASH_MULTIPLIER) / BPS_DENOMINATOR;
                totalSlashedWeight += (a.baseWeight - newWeight);
                a.dynamicWeight = newWeight;
                emit CrashShieldActivated(a.token, newWeight);
            } else {
                emit CrashShieldDeactivated(a.token, a.baseWeight);
            }
        }

        if (totalSlashedWeight > 0) {
            if (healthyStableCount > 0) {
                uint256 extra = totalSlashedWeight / healthyStableCount;
                for (uint i = 0; i < basket.length; i++) if (basket[i].isStable && basket[i].dynamicWeight > 0) basket[i].dynamicWeight += extra;
            } else if (healthyRiskCount > 0) {
                uint256 extra = totalSlashedWeight / healthyRiskCount;
                for (uint i = 0; i < basket.length; i++) if (!basket[i].isStable && basket[i].token != WETH && basket[i].dynamicWeight > 0) basket[i].dynamicWeight += extra;
            }
        }
    }

    function _getOraclePrice(address _oracle) internal view returns (uint256) {
        try AggregatorV3Interface(_oracle).latestRoundData() returns (uint80, int256 price, uint256, uint256 updatedAt, uint80) {
            if (block.timestamp - updatedAt > ORACLE_TIMEOUT || price <= 0) return 0;
            return uint256(price);
        } catch { return 0; }
    }

    function _convertToEth(Asset memory _a, uint256 _amt) internal view returns (uint256) {
        uint256 pE = _getOraclePrice(WETH_ORACLE); uint256 pA = _getOraclePrice(_a.oracle);
        if (pE == 0 || pA == 0) return 0;
        uint256 val = (_amt * pA) / pE;
        uint8 d = IERC20Metadata(_a.token).decimals();
        return d < 18 ? val * (10**(18-d)) : val / (10**(d-18));
    }

    function _convertEthToAsset(Asset memory _a, uint256 _ethAmt) internal view returns (uint256) {
        uint256 pE = _getOraclePrice(WETH_ORACLE); uint256 pA = _getOraclePrice(_a.oracle);
        if (pE == 0 || pA == 0) return 0;
        uint256 val = (_ethAmt * pE) / pA;
        uint8 d = IERC20Metadata(_a.token).decimals();
        return d < 18 ? val / (10**(18-d)) : val * (10**(d-18));
    }

    function _checkSequencer() internal view {
        (, int256 answer, uint256 startedAt, , ) = AggregatorV3Interface(SEQUENCER_FEED).latestRoundData();
        if (answer == 1 || (block.timestamp - startedAt <= 3600)) revert SequencerDown();
    }

    function incentivizedRebalance(uint256 assetIndex, bool isWethToAsset, uint256 amountToSwap) external nonReentrant {
        if (_getOraclePrice(WETH_ORACLE) == 0) revert OracleDead();
        if (assetIndex >= basket.length) revert InvalidIndex();
        Asset memory a = basket[assetIndex];
        if (a.token == WETH) revert CannotSwapSameToken();
        if (_getOraclePrice(a.oracle) == 0) revert OracleDead();

        uint256 minSwapRequired = IWETH(WETH).balanceOf(address(this)) / 100; 
        if (minSwapRequired < 0.01 ether) minSwapRequired = 0.01 ether; 

        uint256 ethEquivalentAmount = isWethToAsset ? amountToSwap : _convertToEth(a, amountToSwap);
        if (ethEquivalentAmount < minSwapRequired) revert SwapVolumeTooLow();

        refreshWeights();
        uint256 targetAssetEthValue = (_calculateTotalEthValue(0) * a.dynamicWeight) / BPS_DENOMINATOR;
        uint256 currentAssetEthValue = _convertToEth(a, IERC20(a.token).balanceOf(address(this)));
        uint256 out;

        if (isWethToAsset) {
            if (currentAssetEthValue >= targetAssetEthValue) revert RebalanceNotNeeded();
            uint256 maxEthToSwap = targetAssetEthValue - currentAssetEthValue;
            uint256 availableWeth = IWETH(WETH).balanceOf(address(this));
            availableWeth = availableWeth > stabilityFund ? availableWeth - stabilityFund : 0;
            
            if (maxEthToSwap > availableWeth) maxEthToSwap = availableWeth;
            if (amountToSwap > maxEthToSwap) amountToSwap = maxEthToSwap; 
            if (amountToSwap == 0) revert RebalanceNotNeeded(); 

            uint256 minOut = _convertEthToAsset(a, amountToSwap);
            minOut -= (minOut * maxInternalSlippage) / BPS_DENOMINATOR;

            IERC20(WETH).approve(UNISWAP_ROUTER, amountToSwap);
            out = ISwapRouter(UNISWAP_ROUTER).exactInputSingle(ISwapRouter.ExactInputSingleParams({
                tokenIn: WETH, tokenOut: a.token, fee: a.poolFee, recipient: address(this),
                amountIn: amountToSwap, amountOutMinimum: minOut, sqrtPriceLimitX96: 0
            }));
            emit Rebalanced(msg.sender, WETH, a.token, amountToSwap, out);
        } else {
            if (currentAssetEthValue <= targetAssetEthValue) revert RebalanceNotNeeded();
            uint256 maxAssetToSwap = _convertEthToAsset(a, currentAssetEthValue - targetAssetEthValue);
            if (amountToSwap > maxAssetToSwap) amountToSwap = maxAssetToSwap; 

            uint256 minOut = _convertToEth(a, amountToSwap);
            minOut -= (minOut * maxInternalSlippage) / BPS_DENOMINATOR;

            IERC20(a.token).approve(UNISWAP_ROUTER, amountToSwap);
            out = ISwapRouter(UNISWAP_ROUTER).exactInputSingle(ISwapRouter.ExactInputSingleParams({
                tokenIn: a.token, tokenOut: WETH, fee: a.poolFee, recipient: address(this),
                amountIn: amountToSwap, amountOutMinimum: minOut, sqrtPriceLimitX96: 0
            }));
            emit Rebalanced(msg.sender, a.token, WETH, amountToSwap, out);
        }

        if (stabilityFund >= 0.0001 ether) {
            stabilityFund -= 0.0001 ether;
            IWETH(WETH).withdraw(0.0001 ether);
            (bool success, ) = payable(msg.sender).call{value: 0.0001 ether}("");
            if (!success) revert TransferFailed();
        }
    }

    // ==========================================
    // 5. MAINTENANCE & YIELD
    // ==========================================
    function updateMaxSlippage(uint256 newMaxSlippage) external onlyOwner {
        if (newMaxSlippage > 1000) revert MaxSlippageExceeded();
        uint256 oldSlippage = maxInternalSlippage;
        maxInternalSlippage = newMaxSlippage;
        emit MaxSlippageUpdated(oldSlippage, newMaxSlippage);
    }

    function getDynamicReserve() public view returns (uint256) {
        uint256 dynamicReserve = _calculateTotalEthValue(0) / 1000; 
        if (dynamicReserve < reserveFloor) return reserveFloor;
        if (dynamicReserve > reserveCeiling) return reserveCeiling;
        return dynamicReserve;
    }

    function _autoDistributeYield() internal {
        uint256 currentReserve = getDynamicReserve();
        if (block.timestamp >= lastYieldDistribution + YIELD_INTERVAL && stabilityFund > currentReserve) {
            uint256 excess = stabilityFund - currentReserve;
            stabilityFund = currentReserve;
            lastYieldDistribution = block.timestamp;
            emit YieldDistributed(excess);
        }
    }
    
    function distributeYield() external {
        if (block.timestamp < lastYieldDistribution + YIELD_INTERVAL) revert TimeNotPassed();
        uint256 currentReserve = getDynamicReserve();
        if (stabilityFund <= currentReserve) revert NoExcessYield();
        
        uint256 excess = stabilityFund - currentReserve;
        stabilityFund = currentReserve; 
        lastYieldDistribution = block.timestamp;
        emit YieldDistributed(excess);
    }

    function updateFounderWallet(address payable newWallet) external onlyFounder {
        if (newWallet == address(0)) revert InvalidAddress();
        founderWallet = newWallet;
    }

    function updateOracle(uint256 basketIndex, address newOracle) external onlyOwner {
        if (basketIndex >= basket.length || newOracle == address(0)) revert InvalidIndex();
        address oldOracle = basket[basketIndex].oracle;
        basket[basketIndex].oracle = newOracle;
        emit OracleUpdated(oldOracle, newOracle);
    }

    function updateWethOracle(address newOracle) external onlyOwner {
        if (newOracle == address(0)) revert InvalidAddress();
        address oldOracle = WETH_ORACLE;
        WETH_ORACLE = newOracle;
        emit OracleUpdated(oldOracle, newOracle);
    }

    function updateReserveBounds(uint256 _newFloor, uint256 _newCeiling) external onlyOwner {
        if (_newFloor > _newCeiling) revert InvalidBounds();
        reserveFloor = _newFloor;
        reserveCeiling = _newCeiling;
        emit ReserveBoundsUpdated(_newFloor, _newCeiling);
    }

    function safeSwap(address tIn, address tOut, uint24 fee, uint256 amtIn, uint256 mOut) public returns (uint256) {
        if (msg.sender != address(this)) revert Unauthorized();
        IERC20(tIn).approve(UNISWAP_ROUTER, amtIn);
        return ISwapRouter(UNISWAP_ROUTER).exactInputSingle(ISwapRouter.ExactInputSingleParams({
            tokenIn: tIn, tokenOut: tOut, fee: fee, recipient: address(this),
            amountIn: amtIn, amountOutMinimum: mOut, sqrtPriceLimitX96: 0
        }));
    }

    function renounceOwnership() external onlyOwner {
        address oldOwner = owner;
        owner = address(0);
        emit OwnershipTransferred(oldOwner, address(0));
        emit ProtocolLockedForever();
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidAddress();
        address oldOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    receive() external payable {}
}