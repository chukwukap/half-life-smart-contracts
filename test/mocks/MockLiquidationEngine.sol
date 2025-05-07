// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {LiquidationEngine} from "../../src/LiquidationEngine.sol";

/// @title MockLiquidationEngine
/// @notice Mock implementation of LiquidationEngine for testing
contract MockLiquidationEngine is LiquidationEngine {
    /// @notice Initialize the contract
    /// @param _positionManager The PositionManager contract address
    function initialize(address _positionManager) external override {
        __Ownable_init(msg.sender);
        __Pausable_init();
        positionManager = _positionManager;
        liquidationPenalty = 500; // 5% penalty
    }

    /// @notice Check if a position can be liquidated
    /// @param positionId The position ID
    /// @param currentIndexValue The current index value
    /// @param maintenanceMargin The maintenance margin requirement
    /// @return isLiquidatable Whether the position can be liquidated
    function canLiquidate(
        uint256 positionId,
        uint256 currentIndexValue,
        uint256 maintenanceMargin
    ) external view override returns (bool isLiquidatable) {
        // Mock implementation always returns false
        return false;
    }

    /// @notice Liquidate a position
    /// @param positionId The position ID
    /// @param currentIndexValue The current index value
    /// @param maintenanceMargin The maintenance margin requirement
    /// @return pnl The profit or loss from the position
    /// @return penalty The penalty applied to the position
    function liquidate(
        uint256 positionId,
        uint256 currentIndexValue,
        uint256 maintenanceMargin
    ) external override returns (int256 pnl, uint256 penalty) {
        // Mock implementation returns zero values
        return (0, 0);
    }
}
