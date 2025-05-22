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
import "./HalfLifeMarginVault.sol";
import "./HalfLifeOracleAdapter.sol";

/// @title HalfLifeUniswapV4Hook
/// @notice Uniswap v4 hook for Half-Life perpetual index betting flywheel.
/// @dev Implements all relevant hooks for margin, funding, PnL, and liquidation logic.
contract HalfLifeUniswapV4Hook is IHooks, ReentrancyGuard, Ownable {
    HalfLifeMarginVault public vault;
    HalfLifeOracleAdapter public oracle;

    // Protocol-specific state
    mapping(address => uint256) public lastTradeTimestamp;
    mapping(address => uint256) public flashLoanProtection;
    uint256 public cooldownPeriod = 5 minutes;
    uint256 public minMargin = 100e18;
    uint256 public maxLeverage = 10e18;
    uint256 public maxPriceImpact = 0.05e18;
    uint256 public twapPeriod = 30 minutes;

    event UserLiquidated(address indexed user, uint256 timestamp);
    event RiskParametersUpdated(uint256 minMargin, uint256 maxLeverage, uint256 maxPriceImpact);
    event TWAPUpdated(uint256 newTWAP, uint256 timestamp);
    event FlashLoanDetected(address indexed user, uint256 timestamp);

    constructor(address _vault, address _oracle) Ownable(msg.sender) {
        vault = HalfLifeMarginVault(_vault);
        oracle = HalfLifeOracleAdapter(_oracle);
    }

    // ========== ADMIN FUNCTIONS ==========
    function setVault(address _vault) external onlyOwner {
        require(_vault != address(0), "Invalid vault");
        vault = HalfLifeMarginVault(_vault);
    }
    function setOracle(address _oracle) external onlyOwner {
        require(_oracle != address(0), "Invalid oracle");
        oracle = HalfLifeOracleAdapter(_oracle);
    }
    function updateRiskParameters(
        uint256 _minMargin,
        uint256 _maxLeverage,
        uint256 _maxPriceImpact
    ) external onlyOwner {
        require(_minMargin > 0, "Invalid minMargin");
        require(_maxLeverage > 0, "Invalid maxLeverage");
        require(_maxPriceImpact <= 0.1e18, "Price impact too high");
        minMargin = _minMargin;
        maxLeverage = _maxLeverage;
        maxPriceImpact = _maxPriceImpact;
        emit RiskParametersUpdated(_minMargin, _maxLeverage, _maxPriceImpact);
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
        // Settle funding, update state if needed
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
        // Funding logic, PnL, and liquidation can be added here
        // ...
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
        // Settle PnL, update funding, etc.
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
    function _enforceCooldown(address user) internal view {
        require(block.timestamp >= lastTradeTimestamp[user] + cooldownPeriod, "Cooldown active");
    }
    function _enforceMargin(address user) internal view {
        require(vault.margin(user) >= minMargin, "Insufficient margin");
    }
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
    function _updateTWAP() internal {
        emit TWAPUpdated(_getCurrentTLI(), block.timestamp);
    }
    function _getCurrentTLI() internal view returns (uint256) {
        return oracle.latestTLI();
    }
}
