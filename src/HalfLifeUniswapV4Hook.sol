// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { IHooks } from "v4-core/interfaces/IHooks.sol";
import { PoolKey } from "v4-core/types/PoolKey.sol";
import { BalanceDelta } from "v4-core/types/BalanceDelta.sol";
import { BalanceDeltaLibrary } from "v4-core/types/BalanceDelta.sol";
import { IPoolManager } from "v4-core/interfaces/IPoolManager.sol";
import { BeforeSwapDelta } from "v4-core/types/BeforeSwapDelta.sol";
import { BeforeSwapDeltaLibrary } from "v4-core/types/BeforeSwapDelta.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IHalfLifeMarginVault.sol";
import "./interfaces/IHalfLifeOracleAdapter.sol";

/// @title HalfLifeUniswapV4Hook
/// @notice Uniswap v4 hook for Half-Life perpetual index betting flywheel.
/// @dev Implements all relevant hooks for margin, funding, PnL, and liquidation logic.
contract HalfLifeUniswapV4Hook is IHooks, ReentrancyGuard, Ownable {
    IHalfLifeMarginVault public vault;
    IHalfLifeOracleAdapter public oracle;

    // Protocol-specific state
    mapping(address => int256) public userPosition; // positive = long, negative = short
    mapping(address => uint256) public userEntryTLI; // TLI at position entry
    mapping(address => uint256) public lastTradeTimestamp;
    mapping(address => uint256) public flashLoanProtection;
    mapping(address => bool) public isLiquidated;

    uint256 public cooldownPeriod = 5 minutes;
    uint256 public minMargin = 100e18;
    uint256 public maxLeverage = 10e18;
    uint256 public maxPositionSize = 1000000e18; // 1 million
    uint256 public maxPriceImpact = 0.05e18;
    uint256 public twapPeriod = 30 minutes;
    uint256 public maintenanceMarginRatio = 0.1e18; // 10%
    uint256 public fundingInterval = 1 hours;
    uint256 public lastFundingTime;
    uint256 public fundingRateCap = 0.01e18; // 1% per interval
    uint256 public minValidTLI = 0.1e18;
    uint256 public maxValidTLI = 10e18;

    // Funding state
    int256 public globalFundingRate; // signed, can be positive or negative
    uint256 public lastFundingTLI;

    event UserLiquidated(address indexed user, uint256 timestamp);
    event PositionOpened(address indexed user, int256 size, uint256 entryTLI);
    event PositionClosed(address indexed user, int256 size, int256 pnl, uint256 exitTLI);
    event FundingPaid(address indexed user, int256 fundingAmount);
    event RiskParametersUpdated(
        uint256 minMargin,
        uint256 maxLeverage,
        uint256 maxPositionSize,
        uint256 maxPriceImpact
    );
    event TWAPUpdated(uint256 newTWAP, uint256 timestamp);
    event FlashLoanDetected(address indexed user, uint256 timestamp);
    event OracleStale(uint256 lastUpdate, uint256 heartbeat);

    constructor(address _vault, address _oracle) Ownable(msg.sender) {
        vault = IHalfLifeMarginVault(_vault);
        oracle = IHalfLifeOracleAdapter(_oracle);
        lastFundingTime = block.timestamp;
        lastFundingTLI = 1e18; // initialize to 1 for safety
    }

    // ========== ADMIN FUNCTIONS ==========
    function setVault(address _vault) external onlyOwner {
        require(_vault != address(0), "Invalid vault");
        vault = IHalfLifeMarginVault(_vault);
    }
    function setOracle(address _oracle) external onlyOwner {
        require(_oracle != address(0), "Invalid oracle");
        oracle = IHalfLifeOracleAdapter(_oracle);
    }
    function updateRiskParameters(
        uint256 _minMargin,
        uint256 _maxLeverage,
        uint256 _maxPositionSize,
        uint256 _maxPriceImpact
    ) external onlyOwner {
        require(_minMargin > 0, "Invalid minMargin");
        require(_maxLeverage > 0, "Invalid maxLeverage");
        require(_maxPositionSize > 0, "Invalid maxPositionSize");
        require(_maxPriceImpact <= 0.1e18, "Price impact too high");
        minMargin = _minMargin;
        maxLeverage = _maxLeverage;
        maxPositionSize = _maxPositionSize;
        maxPriceImpact = _maxPriceImpact;
        emit RiskParametersUpdated(_minMargin, _maxLeverage, _maxPositionSize, _maxPriceImpact);
    }
    function updateCooldownPeriod(uint256 _cooldownPeriod) external onlyOwner {
        require(_cooldownPeriod <= 1 hours, "Cooldown too long");
        cooldownPeriod = _cooldownPeriod;
    }
    function updateTWAPPeriod(uint256 _twapPeriod) external onlyOwner {
        require(_twapPeriod >= 5 minutes && _twapPeriod <= 24 hours, "Invalid TWAP period");
        twapPeriod = _twapPeriod;
    }

    // ========== HOOKS IMPLEMENTATION ==========
    // --- Initialization Hooks ---
    function beforeInitialize(address, PoolKey calldata, uint160) external pure override returns (bytes4) {
        return IHooks.beforeInitialize.selector;
    }
    function afterInitialize(address, PoolKey calldata, uint160, int24) external pure override returns (bytes4) {
        return IHooks.afterInitialize.selector;
    }

    // --- Add Liquidity Hooks ---
    function beforeAddLiquidity(
        address sender,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external override nonReentrant returns (bytes4) {
        _enforceCooldown(sender);
        _enforceMargin(sender);
        require(!isLiquidated[sender], "User is liquidated");
        return IHooks.beforeAddLiquidity.selector;
    }
    function afterAddLiquidity(
        address sender,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external override nonReentrant returns (bytes4, BalanceDelta) {
        _updateTWAP();
        return (IHooks.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    // --- Remove Liquidity Hooks ---
    function beforeRemoveLiquidity(
        address sender,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external override nonReentrant returns (bytes4) {
        _enforceCooldown(sender);
        _enforceMargin(sender);
        require(!isLiquidated[sender], "User is liquidated");
        return IHooks.beforeRemoveLiquidity.selector;
    }
    function afterRemoveLiquidity(
        address sender,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external override nonReentrant returns (bytes4, BalanceDelta) {
        _updateTWAP();
        return (IHooks.afterRemoveLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    // --- Swap Hooks ---
    function beforeSwap(
        address sender,
        PoolKey calldata,
        IPoolManager.SwapParams calldata params,
        bytes calldata
    ) external override nonReentrant returns (bytes4, BeforeSwapDelta, uint24) {
        _enforceCooldown(sender);
        _enforceMargin(sender);
        _checkFlashLoan(sender);
        require(!isLiquidated[sender], "User is liquidated");
        _enforceOracleFresh();
        _enforceLeverage(sender, params.amountSpecified);
        _enforcePositionSize(sender, params.amountSpecified);
        _enforcePriceImpact(params.amountSpecified);

        // Settle funding for all users if interval passed
        if (block.timestamp >= lastFundingTime + fundingInterval) {
            _settleFundingAll();
            lastFundingTime = block.timestamp;
        }

        // If user has no open position, open new position
        if (userPosition[sender] == 0) {
            userPosition[sender] = int256(params.amountSpecified);
            userEntryTLI[sender] = _getCurrentTLI();
            emit PositionOpened(sender, int256(params.amountSpecified), userEntryTLI[sender]);
        } else {
            // If user has an open position, settle PnL and update position
            _settlePnL(sender);
            userPosition[sender] += int256(params.amountSpecified);
            // If position is closed, reset entry TLI
            if (userPosition[sender] == 0) {
                userEntryTLI[sender] = 0;
            }
        }

        // Liquidate if margin is too low after trade
        if (_isLiquidatable(sender)) {
            _liquidate(sender);
        }

        lastTradeTimestamp[sender] = block.timestamp;
        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function afterSwap(
        address sender,
        PoolKey calldata,
        IPoolManager.SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) external override nonReentrant returns (bytes4, int128) {
        _settlePnL(sender);
        _updateTWAP();
        return (IHooks.afterSwap.selector, 0);
    }

    // --- Donate Hooks ---
    function beforeDonate(
        address,
        PoolKey calldata,
        uint256,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IHooks.beforeDonate.selector;
    }
    function afterDonate(
        address,
        PoolKey calldata,
        uint256,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IHooks.afterDonate.selector;
    }

    // ========== INTERNAL HELPERS ==========
    /// @dev Settle funding for all users (demo: only sender, real: off-chain or event-driven)
    function _settleFundingAll() internal {
        // For demo, only settle for msg.sender (called in beforeSwap)
        // Funding = (currentTLI - lastFundingTLI) * fundingRate * positionSize
        // Funding rate is capped
        int256 fundingRate = _calculateFundingRate();
        globalFundingRate = fundingRate;
        lastFundingTLI = _getCurrentTLI();
        // In a real system, this would iterate over all users
    }

    /// @dev Settle PnL and funding for a user
    function _settlePnL(address user) internal {
        if (userPosition[user] == 0 || isLiquidated[user]) return;
        uint256 exitTLI = _getCurrentTLI();
        int256 pnl = 0;
        if (userPosition[user] > 0) {
            // Long: (Exit TLI - Entry TLI) * Position Size
            pnl = ((int256(exitTLI) - int256(userEntryTLI[user])) * userPosition[user]) / 1e18;
        } else if (userPosition[user] < 0) {
            // Short: (Entry TLI - Exit TLI) * |Position Size|
            pnl = ((int256(userEntryTLI[user]) - int256(exitTLI)) * (-userPosition[user])) / 1e18;
        }
        // Apply PnL to margin vault (positive: add, negative: slash)
        if (pnl > 0) {
            vault.transfer(user, uint256(pnl));
        } else if (pnl < 0) {
            vault.slash(user, uint256(-pnl));
        }
        emit PositionClosed(user, userPosition[user], pnl, exitTLI);
        userPosition[user] = 0;
        userEntryTLI[user] = 0;
    }

    /// @dev Liquidate a user if margin is too low
    function _liquidate(address user) internal {
        isLiquidated[user] = true;
        vault.slash(user, vault.margin(user));
        emit UserLiquidated(user, block.timestamp);
    }

    /// @dev Check if a user is liquidatable
    function _isLiquidatable(address user) internal view returns (bool) {
        if (userPosition[user] == 0 || isLiquidated[user]) return false;
        uint256 margin = vault.margin(user);
        uint256 notional = (uint256(userPosition[user] > 0 ? userPosition[user] : -userPosition[user]) *
            _getCurrentTLI()) / 1e18;
        uint256 minMarginRequired = (notional * maintenanceMarginRatio) / 1e18;
        return margin < minMarginRequired;
    }

    /// @dev Enforce cooldown between trades
    function _enforceCooldown(address user) internal view {
        require(block.timestamp >= lastTradeTimestamp[user] + cooldownPeriod, "Cooldown active");
    }
    /// @dev Enforce minimum margin
    function _enforceMargin(address user) internal view {
        require(vault.margin(user) >= minMargin, "Insufficient margin");
    }
    /// @dev Enforce leverage limits
    function _enforceLeverage(address user, int256 amount) internal view {
        uint256 margin = vault.margin(user);
        int256 newSize = userPosition[user] + amount;
        uint256 notional = (uint256(newSize > 0 ? newSize : -newSize) * _getCurrentTLI()) / 1e18;
        require(margin > 0, "Margin must be positive");
        require((notional * 1e18) / margin <= maxLeverage, "Leverage too high");
    }
    /// @dev Enforce position size limits
    function _enforcePositionSize(address user, int256 amount) internal view {
        int256 newSize = userPosition[user] + amount;
        require(uint256(newSize > 0 ? newSize : -newSize) <= maxPositionSize, "Position size too large");
    }
    /// @dev Enforce price impact (stub, real implementation would use pool state)
    function _enforcePriceImpact(int256 /*amount*/) internal view {
        // TODO: Implement real price impact check using pool state
        // For now, assume always within limit
    }
    /// @dev Flash loan protection
    function _checkFlashLoan(address user) internal {
        uint256 currentTime = block.timestamp;
        uint256 lastTrade = lastTradeTimestamp[user];
        if (currentTime == lastTrade) {
            flashLoanProtection[user]++;
            if (flashLoanProtection[user] > 3) {
                emit FlashLoanDetected(user, currentTime);
                revert("Flash loan detected");
            }
        } else {
            flashLoanProtection[user] = 1;
        }
    }
    /// @dev Update TWAP (emit event for off-chain tracking)
    function _updateTWAP() internal {
        emit TWAPUpdated(_getCurrentTLI(), block.timestamp);
    }
    /// @dev Get current TLI from oracle, revert if stale or out of range
    function _getCurrentTLI() internal view returns (uint256) {
        uint256 tli = oracle.latestTLI();
        require(tli >= minValidTLI && tli <= maxValidTLI, "TLI out of range");
        return tli;
    }
    /// @dev Enforce oracle data is fresh
    function _enforceOracleFresh() internal view {
        uint256 lastUpdate = oracle.state().lastUpdate;
        uint256 heartbeat = oracle.state().heartbeat;
        if (block.timestamp > lastUpdate + heartbeat) {
            emit OracleStale(lastUpdate, heartbeat);
            revert("Oracle data is stale");
        }
    }
    /// @dev Calculate funding rate (simple capped difference for demo)
    function _calculateFundingRate() internal view returns (int256) {
        uint256 tli = _getCurrentTLI();
        int256 diff = int256(tli) - int256(lastFundingTLI);
        int256 rate = (diff * 1e18) / int256(lastFundingTLI);
        if (rate > int256(fundingRateCap)) return int256(fundingRateCap);
        if (rate < -int256(fundingRateCap)) return -int256(fundingRateCap);
        return rate;
    }
}
