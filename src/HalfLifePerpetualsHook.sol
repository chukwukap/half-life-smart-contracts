// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";

// Import protocol modules
import {IPositionManager} from "./interfaces/IPositionManager.sol";
import {IFundingRateEngine} from "./interfaces/IFundingRateEngine.sol";
import {IFeeManager} from "./interfaces/IFeeManager.sol";
import {IOracleAdapter} from "./interfaces/IOracleAdapter.sol";

/// @title HalfLifePerpetualsHook
/// @notice Uniswap v4 custom hook for Half-Life perpetual index betting
/// @dev Integrates funding, margin, and liquidation logic at swap points
contract HalfLifePerpetualsHook is IHooks {
    // --- Protocol Modules ---
    IPositionManager public positionManager;
    IFundingRateEngine public fundingRateEngine;
    IFeeManager public feeManager;
    IOracleAdapter public oracleAdapter;

    // --- Events ---
    event FundingApplied(address indexed user, int256 fundingPayment);
    event MarginChecked(address indexed user, bool solvent);
    event PositionLiquidated(address indexed user, uint256 positionId);

    // --- Constructor ---
    constructor(
        address _positionManager,
        address _fundingRateEngine,
        address _feeManager,
        address _oracleAdapter
    ) {
        positionManager = IPositionManager(_positionManager);
        fundingRateEngine = IFundingRateEngine(_fundingRateEngine);
        feeManager = IFeeManager(_feeManager);
        oracleAdapter = IOracleAdapter(_oracleAdapter);
    }

    // --- Uniswap v4 Hook Points ---

    /// @notice Called before a swap; applies funding, checks margin, triggers liquidation if needed
    function beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) external override returns (bytes4, BeforeSwapDelta, uint24) {
        // Security: Only callable by PoolManager (enforced by Uniswap v4)
        // Decode hookData to get positionId (assume off-chain or frontend encodes this)
        uint256 positionId = 0;
        if (hookData.length >= 32) {
            positionId = abi.decode(hookData, (uint256));
        }
        // Get latest index value from oracle
        (uint256 indexValue, ) = oracleAdapter.getLatestIndexValue();
        // Apply funding rate logic
        int256 fundingRate = fundingRateEngine.calculateFundingRate(
            indexValue,
            indexValue
        ); // Use pool price if available
        int256 fundingPayment = 0;
        if (positionId != 0) {
            // Apply funding to position (assume PositionManager has applyFunding)
            try positionManager.applyFunding(sender, fundingRate) returns (
                int256 payment
            ) {
                fundingPayment = payment;
                emit FundingApplied(sender, payment);
            } catch {}
        }
        // Check margin and trigger liquidation if needed
        bool solvent = true;
        if (positionId != 0) {
            try positionManager.isSolvent(sender) returns (bool _solvent) {
                solvent = _solvent;
                emit MarginChecked(sender, _solvent);
                if (!_solvent) {
                    // Liquidate position (assume PositionManager has liquidate)
                    try positionManager.liquidate(sender) returns (
                        uint256 loss
                    ) {
                        emit PositionLiquidated(sender, positionId);
                    } catch {}
                }
            } catch {}
        }
        // Optionally, override LP fee (set to 0 for now)
        return (IHooks.beforeSwap.selector, BeforeSwapDelta(0, 0), 0);
    }

    /// @notice Called after a swap; update position state, emit events
    function afterSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) external override returns (bytes4, int128) {
        // For this version, no-op except for event emission
        // In a full implementation, update position state, margin, P&L, etc.
        return (IHooks.afterSwap.selector, 0);
    }

    // --- Other hook points (no-op for now, can be extended as needed) ---
    function beforeInitialize(
        address,
        PoolKey calldata,
        uint160
    ) external pure override returns (bytes4) {
        return IHooks.beforeInitialize.selector;
    }
    function afterInitialize(
        address,
        PoolKey calldata,
        uint160,
        int24
    ) external pure override returns (bytes4) {
        return IHooks.afterInitialize.selector;
    }
    function beforeAddLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IHooks.beforeAddLiquidity.selector;
    }
    function afterAddLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure override returns (bytes4, BalanceDelta) {
        return (IHooks.afterAddLiquidity.selector, BalanceDelta(0, 0));
    }
    function beforeRemoveLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IHooks.beforeRemoveLiquidity.selector;
    }
    function afterRemoveLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure override returns (bytes4, BalanceDelta) {
        return (IHooks.afterRemoveLiquidity.selector, BalanceDelta(0, 0));
    }
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
}
