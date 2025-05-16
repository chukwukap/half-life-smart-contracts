// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Import the Uniswap v4 IHooks interface (update the import path as needed for your setup)
import { IHooks } from "v4-core/interfaces/IHooks.sol";
import { PoolKey } from "v4-core/types/PoolKey.sol";
import { BalanceDelta } from "v4-core/types/BalanceDelta.sol";
import { BalanceDeltaLibrary } from "v4-core/types/BalanceDelta.sol";
import { IPoolManager } from "v4-core/interfaces/IPoolManager.sol";
import { BeforeSwapDelta } from "v4-core/types/BeforeSwapDelta.sol";
import { BeforeSwapDeltaLibrary } from "v4-core/types/BeforeSwapDelta.sol";
import "./HalfLifePerpetualPool.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title HalfLifeUniswapV4Hook
/// @notice Uniswap v4 hook for Half-Life perpetual index betting flywheel.
/// @dev Implements all relevant hooks for margin, funding, PnL, and liquidation logic.
contract HalfLifeUniswapV4Hook is IHooks, ReentrancyGuard, Ownable {
    HalfLifePerpetualPool public immutable pool;

    // Core parameters
    uint256 public maxPositionSize = 1000000e18; // 1M units
    uint256 public minPositionSize = 100e18; // 100 units
    uint256 public maxLeverage = 10e18; // 10x leverage
    uint256 public cooldownPeriod;
    uint256 public twapPeriod = 30 minutes;
    uint256 public maxPriceImpact = 0.05e18; // 5% max price impact

    // User state tracking
    mapping(address => uint256) public lastTradeTimestamp;
    mapping(address => uint256) public totalVolume24h;
    mapping(address => uint256) public lastTradePrice;
    mapping(address => uint256) public flashLoanProtection;

    /// @notice Emitted when a user is liquidated by the hook
    event UserLiquidated(address indexed user, uint256 timestamp);
    event PositionSizeUpdated(address indexed user, int256 newSize);
    event RiskParametersUpdated(uint256 maxSize, uint256 minSize, uint256 maxLeverage);
    event TWAPUpdated(uint256 newTWAP, uint256 timestamp);
    event FlashLoanDetected(address indexed user, uint256 timestamp);

    /// @notice Set the perpetual pool address and initial parameters
    /// @param _pool The address of the HalfLifePerpetualPool contract
    constructor(address _pool) Ownable(msg.sender) {
        require(_pool != address(0), "HalfLife: Pool address cannot be zero");
        pool = HalfLifePerpetualPool(_pool);
        cooldownPeriod = 5 minutes;
    }

    // ========== IHooks INTERFACE IMPLEMENTATION ==========

    // --- Initialization Hooks ---

    /// @inheritdoc IHooks
    function beforeInitialize(address, PoolKey calldata, uint160) external override returns (bytes4) {
        // No-op for this implementation, but must return selector
        return IHooks.beforeInitialize.selector;
    }

    /// @inheritdoc IHooks
    function afterInitialize(address, PoolKey calldata, uint160, int24) external override returns (bytes4) {
        // No-op for this implementation, but must return selector
        return IHooks.afterInitialize.selector;
    }

    // --- Add Liquidity Hooks ---

    /// @inheritdoc IHooks
    function beforeAddLiquidity(
        address sender,
        PoolKey calldata, // key
        IPoolManager.ModifyLiquidityParams calldata, // params
        bytes calldata // hookData
    ) external override nonReentrant returns (bytes4) {
        // Security: Enforce margin and trigger funding for LP
        _triggerFunding(sender);
        require(pool.hasSufficientMargin(sender), "HalfLife: Insufficient margin for LP");
        if (pool.isLiquidatable(sender)) {
            pool.liquidate(sender);
            emit UserLiquidated(sender, block.timestamp);
        }
        return IHooks.beforeAddLiquidity.selector;
    }

    /// @inheritdoc IHooks
    function afterAddLiquidity(
        address sender,
        PoolKey calldata, // key
        IPoolManager.ModifyLiquidityParams calldata, // params
        BalanceDelta, // delta
        BalanceDelta, // feesAccrued
        bytes calldata // hookData
    ) external override nonReentrant returns (bytes4, BalanceDelta) {
        // Security: Settle PnL for sender
        pool.settlePnL(sender);
        // Return selector and zero delta (no additional token movement)
        return (IHooks.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    // --- Remove Liquidity Hooks ---

    /// @inheritdoc IHooks
    function beforeRemoveLiquidity(
        address sender,
        PoolKey calldata, // key
        IPoolManager.ModifyLiquidityParams calldata, // params
        bytes calldata // hookData
    ) external override nonReentrant returns (bytes4) {
        // Security: Enforce margin and trigger funding for LP
        _triggerFunding(sender);
        require(pool.hasSufficientMargin(sender), "HalfLife: Insufficient margin for LP");
        if (pool.isLiquidatable(sender)) {
            pool.liquidate(sender);
            emit UserLiquidated(sender, block.timestamp);
        }
        return IHooks.beforeRemoveLiquidity.selector;
    }

    /// @inheritdoc IHooks
    function afterRemoveLiquidity(
        address sender,
        PoolKey calldata, // key
        IPoolManager.ModifyLiquidityParams calldata, // params
        BalanceDelta, // delta
        BalanceDelta, // feesAccrued
        bytes calldata // hookData
    ) external override nonReentrant returns (bytes4, BalanceDelta) {
        // Security: Settle PnL for sender
        pool.settlePnL(sender);
        // Return selector and zero delta (no additional token movement)
        return (IHooks.afterRemoveLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    // --- Swap Hooks ---

    /// @inheritdoc IHooks
    function beforeSwap(
        address sender,
        PoolKey calldata, // key
        IPoolManager.SwapParams calldata params,
        bytes calldata // hookData
    ) external override nonReentrant returns (bytes4, BeforeSwapDelta, uint24) {
        // 1. Check cooldown period
        require(block.timestamp >= lastTradeTimestamp[sender] + cooldownPeriod, "HalfLife: Cooldown period active");

        // 2. Check flash loan attack
        _checkFlashLoan(sender, params.amountSpecified);

        // 3. Update volume tracking
        totalVolume24h[sender] += uint256(
            params.amountSpecified > 0 ? params.amountSpecified : -params.amountSpecified
        );

        // 4. Check position size limits
        (int256 currentSize, uint256 margin, , ) = pool.positions(sender);
        int256 newSize = currentSize + params.amountSpecified;
        require(uint256(newSize > 0 ? newSize : -newSize) <= maxPositionSize, "HalfLife: Position size too large");
        require(uint256(newSize > 0 ? newSize : -newSize) >= minPositionSize, "HalfLife: Position size too small");

        // 5. Check leverage limits
        uint256 notional = (uint256(newSize > 0 ? newSize : -newSize) * pool.oracle().latestTLI()) / 1e18;
        require(margin > 0, "HalfLife: Margin must be positive");
        require((notional * 1e18) / margin <= maxLeverage, "HalfLife: Leverage too high");

        // 6. Check price impact
        uint256 currentPrice = _getCurrentPrice();
        uint256 priceImpact = _calculatePriceImpact(currentPrice, params.amountSpecified);
        require(priceImpact <= maxPriceImpact, "HalfLife: Price impact too high");

        // 7. Trigger funding payment for sender
        _triggerFunding(sender);

        // 8. Check margin for sender (trader)
        require(pool.hasSufficientMargin(sender), "HalfLife: Insufficient margin");

        // 9. Liquidate if margin is too low
        if (pool.isLiquidatable(sender)) {
            pool.liquidate(sender);
            emit UserLiquidated(sender, block.timestamp);
        }

        // 10. Update last trade timestamp and price
        lastTradeTimestamp[sender] = block.timestamp;
        lastTradePrice[sender] = currentPrice;

        // Return selector, no delta, and no fee override
        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    /// @inheritdoc IHooks
    function afterSwap(
        address sender,
        PoolKey calldata, // key
        IPoolManager.SwapParams calldata, // params
        BalanceDelta, // delta
        bytes calldata // hookData
    ) external override nonReentrant returns (bytes4, int128) {
        // 1. Settle PnL for sender
        pool.settlePnL(sender);

        // 2. Update position tracking
        (int256 newSize, , , ) = pool.positions(sender);
        emit PositionSizeUpdated(sender, newSize);

        // 3. Reset volume tracking if 24h passed
        if (block.timestamp >= lastTradeTimestamp[sender] + 1 days) {
            totalVolume24h[sender] = 0;
        }

        // 4. Update TWAP
        _updateTWAP();

        // Return selector and zero delta
        return (IHooks.afterSwap.selector, 0);
    }

    // --- Donate Hooks ---

    /// @inheritdoc IHooks
    function beforeDonate(
        address, // sender
        PoolKey calldata, // key
        uint256, // amount0
        uint256, // amount1
        bytes calldata // hookData
    ) external override returns (bytes4) {
        // No-op for this implementation, but must return selector
        return IHooks.beforeDonate.selector;
    }

    /// @inheritdoc IHooks
    function afterDonate(
        address, // sender
        PoolKey calldata, // key
        uint256, // amount0
        uint256, // amount1
        bytes calldata // hookData
    ) external override returns (bytes4) {
        // No-op for this implementation, but must return selector
        return IHooks.afterDonate.selector;
    }

    // ========== ADMIN FUNCTIONS ==========

    /// @notice Update risk parameters
    function updateRiskParameters(
        uint256 _maxPositionSize,
        uint256 _minPositionSize,
        uint256 _maxLeverage,
        uint256 _maxPriceImpact
    ) external onlyOwner {
        require(_maxPositionSize > _minPositionSize, "Invalid size range");
        require(_maxLeverage > 0, "Invalid leverage");
        require(_maxPriceImpact <= 0.1e18, "Price impact too high");

        maxPositionSize = _maxPositionSize;
        minPositionSize = _minPositionSize;
        maxLeverage = _maxLeverage;
        maxPriceImpact = _maxPriceImpact;

        emit RiskParametersUpdated(_maxPositionSize, _minPositionSize, _maxLeverage);
    }

    /// @notice Update cooldown period
    function updateCooldownPeriod(uint256 _cooldownPeriod) external onlyOwner {
        require(_cooldownPeriod <= 1 hours, "Cooldown too long");
        cooldownPeriod = _cooldownPeriod;
    }

    /// @notice Update TWAP period
    function updateTWAPPeriod(uint256 _twapPeriod) external onlyOwner {
        require(_twapPeriod >= 5 minutes && _twapPeriod <= 24 hours, "Invalid TWAP period");
        twapPeriod = _twapPeriod;
    }

    // ========== INTERNAL HELPERS ==========

    /// @dev Triggers funding payment for a user if they have an open position
    function _triggerFunding(address user) internal {
        if (pool.hasOpenPosition(user)) {
            pool.payFunding(user);
        }
    }

    /// @dev Get current price from pool
    function _getCurrentPrice() internal view returns (uint256) {
        return pool.oracle().latestTLI();
    }

    /// @dev Calculate price impact of a trade
    function _calculatePriceImpact(uint256 currentPrice, int256 amount) internal view returns (uint256) {
        if (amount == 0) return 0;
        uint256 absAmount = uint256(amount > 0 ? amount : -amount);
        // FIX: Prevent division by zero
        if (currentPrice == 0) return type(uint256).max;
        return (absAmount * 1e18) / (currentPrice * 1e18);
    }

    /// @dev Check for flash loan attacks
    function _checkFlashLoan(address user, int256 /*amount*/) internal {
        uint256 currentTime = block.timestamp;
        uint256 lastTrade = lastTradeTimestamp[user];

        // If multiple trades in same block, increment protection counter
        if (currentTime == lastTrade) {
            flashLoanProtection[user]++;
            if (flashLoanProtection[user] > 3) {
                emit FlashLoanDetected(user, currentTime);
                revert("HalfLife: Flash loan detected");
            }
        } else {
            flashLoanProtection[user] = 1;
        }
    }

    /// @dev Update TWAP
    function _updateTWAP() internal {
        // Implementation would depend on specific TWAP calculation requirements
        // This is a placeholder for the actual implementation
        emit TWAPUpdated(_getCurrentPrice(), block.timestamp);
    }
}
