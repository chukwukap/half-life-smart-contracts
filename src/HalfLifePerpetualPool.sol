// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "./interfaces/IHalfLifeOracleAdapter.sol";
import "./interfaces/IHalfLifeMarginVault.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/// @title HalfLifePerpetualPool
/// @notice Manages perpetual long/short positions on a token's TLI.
contract HalfLifePerpetualPool is ReentrancyGuard, Ownable {
    using Math for uint256;

    struct Position {
        int256 size; // positive = long, negative = short
        uint256 entryTLI;
        uint256 margin;
        uint256 lastFundingTime;
    }

    struct PoolState {
        uint256 totalLongSize;
        uint256 totalShortSize;
        uint256 totalMargin;
        uint256 totalFees;
    }

    IHalfLifeOracleAdapter public immutable oracle;
    IHalfLifeMarginVault public immutable vault;

    PoolState public poolState;
    mapping(address => Position) public positions;

    // Core parameters
    uint256 public fundingInterval = 1 hours;
    uint256 public fundingRateCap = 0.01e18; // 1% per interval
    uint256 public maintenanceMarginRatio = 0.1e18; // 10% maintenance margin
    uint256 public maxLeverage = 10e18; // 10x leverage
    uint256 public minMargin = 100e18; // Minimum margin required
    uint256 public tradingFee = 0.001e18; // 0.1% trading fee

    // Circuit breaker
    bool public circuitBreaker;
    uint256 public maxDrawdown = 0.2e18; // 20% max drawdown

    event PositionOpened(address indexed user, int256 size, uint256 entryTLI, uint256 margin, uint256 fee);
    event PositionClosed(address indexed user, int256 size, int256 pnl, uint256 exitTLI, uint256 fee);
    event FundingPaid(address indexed user, int256 fundingAmount);
    event Liquidated(address indexed user, int256 size, int256 pnl, uint256 exitTLI, uint256 fee);
    event CircuitBreakerTriggered(uint256 timestamp);
    event CircuitBreakerReset(uint256 timestamp);

    constructor(address _oracle, address _vault) Ownable(msg.sender) {
        oracle = IHalfLifeOracleAdapter(_oracle);
        vault = IHalfLifeMarginVault(_vault);
    }

    function openPosition(int256 size, uint256 marginAmount) external nonReentrant {
        require(!circuitBreaker, "Circuit breaker active");
        require(size != 0, "Zero size");
        require(marginAmount >= minMargin, "Margin too low");
        require(vault.margin(msg.sender) >= marginAmount, "Insufficient margin");

        Position storage pos = positions[msg.sender];
        require(pos.size == 0, "Close existing first");

        // Calculate trading fee
        uint256 fee = (uint256(size > 0 ? size : -size) * tradingFee) / 1e18;
        require(marginAmount > fee, "Margin must cover fee");

        uint256 tli = oracle.latestTLI();
        pos.size = size;
        pos.entryTLI = tli;
        pos.margin = marginAmount - fee;
        pos.lastFundingTime = block.timestamp;

        // Update pool state
        if (size > 0) {
            poolState.totalLongSize += uint256(size);
        } else {
            poolState.totalShortSize += uint256(-size);
        }
        poolState.totalMargin += marginAmount;
        poolState.totalFees += fee;

        // Check circuit breaker
        _checkCircuitBreaker();

        emit PositionOpened(msg.sender, size, tli, marginAmount, fee);
    }

    function closePosition() external nonReentrant {
        Position storage pos = positions[msg.sender];
        require(pos.size != 0, "No open position");

        uint256 tli = oracle.latestTLI();
        int256 pnl = _calculatePnL(pos, tli);

        // Funding payment
        int256 funding = _calculateFunding(pos, tli);
        pnl -= funding;

        // Calculate trading fee
        uint256 fee = (uint256(pos.size > 0 ? pos.size : -pos.size) * tradingFee) / 1e18;

        // Settle
        uint256 payout = pos.margin;
        if (pnl > 0) {
            payout += uint256(pnl);
        } else if (pnl < 0) {
            uint256 loss = uint256(-pnl);
            if (loss >= payout) {
                payout = 0;
            } else {
                payout -= loss;
            }
        }

        // Update pool state
        if (pos.size > 0) {
            poolState.totalLongSize -= uint256(pos.size);
        } else {
            poolState.totalShortSize -= uint256(-pos.size);
        }
        poolState.totalMargin -= pos.margin;
        poolState.totalFees += fee;

        emit PositionClosed(msg.sender, pos.size, pnl, tli, fee);

        // Reset position
        delete positions[msg.sender];
    }

    function payFunding(address user) public {
        Position storage pos = positions[user];
        require(pos.size != 0, "No open position");
        require(block.timestamp >= pos.lastFundingTime + fundingInterval, "Too soon");

        uint256 tli = oracle.latestTLI();
        int256 funding = _calculateFunding(pos, tli);

        // Deduct from margin
        if (funding > 0) {
            uint256 loss = uint256(funding);
            if (loss >= pos.margin) {
                pos.margin = 0;
            } else {
                pos.margin -= loss;
            }
        } else if (funding < 0) {
            pos.margin += uint256(-funding);
        }

        pos.lastFundingTime = block.timestamp;
        emit FundingPaid(user, funding);
    }

    function liquidate(address user) external nonReentrant {
        Position storage pos = positions[user];
        require(pos.size != 0, "No open position");

        uint256 tli = oracle.latestTLI();
        int256 pnl = _calculatePnL(pos, tli);
        int256 funding = _calculateFunding(pos, tli);
        pnl -= funding;

        uint256 payout = pos.margin;
        if (pnl > 0) {
            payout += uint256(pnl);
        } else if (pnl < 0) {
            uint256 loss = uint256(-pnl);
            if (loss >= payout) {
                payout = 0;
            } else {
                payout -= loss;
            }
        }

        // Maintenance margin check
        uint256 notional = (uint256(pos.size > 0 ? pos.size : -pos.size) * tli) / 1e18;
        uint256 minMargin = (notional * maintenanceMarginRatio) / 1e18;
        require(payout < minMargin, "Not eligible for liquidation");

        // Calculate liquidation fee (50% of remaining margin)
        uint256 liquidationFee = payout / 2;

        // Update pool state
        if (pos.size > 0) {
            poolState.totalLongSize -= uint256(pos.size);
        } else {
            poolState.totalShortSize -= uint256(-pos.size);
        }
        poolState.totalMargin -= pos.margin;
        poolState.totalFees += liquidationFee;

        // Slash margin
        vault.slash(user, pos.margin);

        emit Liquidated(user, pos.size, pnl, tli, liquidationFee);

        // Reset position
        delete positions[user];
    }

    function settlePnL(address user) public {
        Position storage pos = positions[user];
        require(pos.size != 0, "No open position");

        uint256 tli = oracle.latestTLI();
        int256 pnl = _calculatePnL(pos, tli);
        pos.margin = pnl > 0 ? pos.margin + uint256(pnl) : pos.margin;
    }

    function hasSufficientMargin(address user) public view returns (bool) {
        Position storage pos = positions[user];
        if (pos.size == 0) return true;

        uint256 tli = oracle.latestTLI();
        int256 pnl = _calculatePnL(pos, tli);
        int256 funding = _calculateFunding(pos, tli);
        pnl -= funding;

        uint256 notional = (uint256(pos.size > 0 ? pos.size : -pos.size) * tli) / 1e18;
        uint256 minMargin = (notional * maintenanceMarginRatio) / 1e18;

        return pos.margin + (pnl > 0 ? uint256(pnl) : 0) >= minMargin;
    }

    function isLiquidatable(address user) public view returns (bool) {
        Position storage pos = positions[user];
        if (pos.size == 0) return false;

        uint256 tli = oracle.latestTLI();
        int256 pnl = _calculatePnL(pos, tli);
        int256 funding = _calculateFunding(pos, tli);
        pnl -= funding;

        uint256 notional = (uint256(pos.size > 0 ? pos.size : -pos.size) * tli) / 1e18;
        uint256 minMargin = (notional * maintenanceMarginRatio) / 1e18;

        return pos.margin + (pnl > 0 ? uint256(pnl) : 0) < minMargin;
    }

    function hasOpenPosition(address user) public view returns (bool) {
        return positions[user].size != 0;
    }

    function _calculatePnL(Position storage pos, uint256 tli) internal view returns (int256) {
        int256 diff = int256(tli) - int256(pos.entryTLI);
        return (diff * pos.size) / 1e18;
    }

    function _calculateFunding(Position storage pos, uint256 tli) internal view returns (int256) {
        int256 premium = ((int256(tli) - int256(pos.entryTLI)) * 1e18) / int256(pos.entryTLI);
        if (premium > int256(fundingRateCap)) premium = int256(fundingRateCap);
        if (premium < -int256(fundingRateCap)) premium = -int256(fundingRateCap);
        return (pos.size * premium) / 1e18;
    }

    function _checkCircuitBreaker() internal {
        if (circuitBreaker) return;

        uint256 totalSize = poolState.totalLongSize + poolState.totalShortSize;
        if (totalSize == 0) return;

        uint256 drawdown = (poolState.totalFees * 1e18) / poolState.totalMargin;
        if (drawdown >= maxDrawdown) {
            circuitBreaker = true;
            emit CircuitBreakerTriggered(block.timestamp);
        }
    }

    function resetCircuitBreaker() external onlyOwner {
        require(circuitBreaker, "Circuit breaker not active");
        circuitBreaker = false;
        emit CircuitBreakerReset(block.timestamp);
    }
}
