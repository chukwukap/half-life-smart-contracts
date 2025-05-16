// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

// Import the Uniswap v4 IHooks interface (update the import path as needed for your setup)
import { IHooks } from "v4-core/interfaces/IHooks.sol";
import { PoolKey } from "v4-core/types/PoolKey.sol";
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
        pool = HalfLifePerpetualPool(_pool);
        cooldownPeriod = 5 minutes;
    }

    // ========== SWAP HOOKS ==========

    /// @notice Called before a swap is executed in the pool
    /// @dev Enforces margin, triggers funding, and liquidates if needed
    function beforeSwap(
        address sender,
        address recipient,
        int256 amount0,
        int256 amount1,
        bytes calldata data
    ) external nonReentrant {
        // 1. Check cooldown period
        require(block.timestamp >= lastTradeTimestamp[sender] + cooldownPeriod, "HalfLife: Cooldown period active");

        // 2. Check flash loan attack
        _checkFlashLoan(sender, amount0);

        // 3. Update volume tracking
        totalVolume24h[sender] += uint256(amount0 > 0 ? amount0 : -amount0);

        // 4. Check position size limits
        int256 newSize = pool.positions(sender).size + amount0;
        require(uint256(newSize > 0 ? newSize : -newSize) <= maxPositionSize, "HalfLife: Position size too large");
        require(uint256(newSize > 0 ? newSize : -newSize) >= minPositionSize, "HalfLife: Position size too small");

        // 5. Check leverage limits
        uint256 margin = pool.positions(sender).margin;
        uint256 notional = (uint256(newSize > 0 ? newSize : -newSize) * pool.oracle().latestTLI()) / 1e18;
        require((notional * 1e18) / margin <= maxLeverage, "HalfLife: Leverage too high");

        // 6. Check price impact
        uint256 currentPrice = _getCurrentPrice();
        uint256 priceImpact = _calculatePriceImpact(currentPrice, amount0);
        require(priceImpact <= maxPriceImpact, "HalfLife: Price impact too high");

        // 7. Trigger funding payment for sender and recipient
        _triggerFunding(sender);
        if (recipient != sender) {
            _triggerFunding(recipient);
        }

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
    }

    /// @notice Called after a swap is executed in the pool
    /// @dev Settle PnL and update position for sender
    function afterSwap(
        address sender,
        address recipient,
        int256 amount0,
        int256 amount1,
        bytes calldata data
    ) external nonReentrant {
        // 1. Settle PnL for sender
        pool.settlePnL(sender);

        // 2. Update position tracking
        int256 newSize = pool.positions(sender).size;
        emit PositionSizeUpdated(sender, newSize);

        // 3. Reset volume tracking if 24h passed
        if (block.timestamp >= lastTradeTimestamp[sender] + 1 days) {
            totalVolume24h[sender] = 0;
        }

        // 4. Update TWAP
        _updateTWAP();
    }

    // ========== LIQUIDITY HOOKS ==========

    /// @notice Called before liquidity is added to the pool
    /// @dev Enforces margin and triggers funding for LP
    function beforeAddLiquidity(
        address sender,
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount,
        bytes calldata data
    ) external nonReentrant {
        _triggerFunding(sender);
        require(pool.hasSufficientMargin(sender), "HalfLife: Insufficient margin for LP");
        if (pool.isLiquidatable(sender)) {
            pool.liquidate(sender);
            emit UserLiquidated(sender, block.timestamp);
        }
    }

    /// @notice Called after liquidity is added to the pool
    function afterAddLiquidity(
        address sender,
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount,
        bytes calldata data
    ) external nonReentrant {
        pool.settlePnL(sender);
    }

    /// @notice Called before liquidity is removed from the pool
    function beforeRemoveLiquidity(
        address sender,
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount,
        bytes calldata data
    ) external nonReentrant {
        _triggerFunding(sender);
        require(pool.hasSufficientMargin(sender), "HalfLife: Insufficient margin for LP");
        if (pool.isLiquidatable(sender)) {
            pool.liquidate(sender);
            emit UserLiquidated(sender, block.timestamp);
        }
    }

    /// @notice Called after liquidity is removed from the pool
    function afterRemoveLiquidity(
        address sender,
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount,
        bytes calldata data
    ) external nonReentrant {
        pool.settlePnL(sender);
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
        return (absAmount * 1e18) / (currentPrice * 1e18);
    }

    /// @dev Check for flash loan attacks
    function _checkFlashLoan(address user, int256 amount) internal {
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

    // ========== ADDITIONAL HOOK IMPLEMENTATIONS ==========

    /// @notice Called before pool initialization
    function beforeInitialize(address sender, PoolKey calldata key, uint160 sqrtPriceX96) external returns (bytes4) {
        // Only allow pool initialization by owner
        require(sender == owner(), "HalfLife: Only owner can initialize");
        return this.beforeInitialize.selector;
    }

    /// @notice Called after pool initialization
    function afterInitialize(
        address sender,
        PoolKey calldata key,
        uint160 sqrtPriceX96,
        int24 tick
    ) external returns (bytes4) {
        // Additional initialization logic if needed
        return this.afterInitialize.selector;
    }

    /// @notice Called before donating to the pool
    function beforeDonate(
        address sender,
        address recipient,
        PoolKey calldata key,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external returns (bytes4) {
        // Validate donation parameters
        require(amount0 > 0 || amount1 > 0, "HalfLife: Invalid donation amounts");
        return this.beforeDonate.selector;
    }

    /// @notice Called after donating to the pool
    function afterDonate(
        address sender,
        address recipient,
        PoolKey calldata key,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external returns (bytes4) {
        // Additional post-donation logic if needed
        return this.afterDonate.selector;
    }
}
