// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ILiquidationEngine
/// @notice Interface for the LiquidationEngine contract in Half-Life protocol
interface ILiquidationEngine {
    /// @notice Emitted when a position is liquidated
    event PositionLiquidated(
        address indexed user,
        uint256 indexed positionId,
        address indexed liquidator,
        int256 pnl,
        uint256 penalty
    );

    /// @notice Check if a position is eligible for liquidation
    /// @param positionId The ID of the position
    /// @param currentIndexValue The current index value
    /// @param maintenanceMargin The maintenance margin requirement
    /// @return canLiquidate True if eligible for liquidation
    function canLiquidate(
        uint256 positionId,
        uint256 currentIndexValue,
        uint256 maintenanceMargin
    ) external view returns (bool canLiquidate);

    /// @notice Trigger liquidation of a position
    /// @param positionId The ID of the position
    /// @param currentIndexValue The current index value
    /// @param maintenanceMargin The maintenance margin requirement
    /// @return pnl The profit or loss from the position
    /// @return penalty The penalty applied to the position
    function liquidate(
        uint256 positionId,
        uint256 currentIndexValue,
        uint256 maintenanceMargin
    ) external returns (int256 pnl, uint256 penalty);

    /// @notice Set the liquidation penalty (onlyOwner or market)
    /// @param penaltyBps The penalty in basis points (1e4 = 100%)
    function setLiquidationPenalty(uint256 penaltyBps) external;

    /// @notice Get the current liquidation penalty
    /// @return penaltyBps The penalty in basis points
    function getLiquidationPenalty() external view returns (uint256 penaltyBps);
}
