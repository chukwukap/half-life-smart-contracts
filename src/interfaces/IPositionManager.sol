// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/// @title IPositionManager
/// @notice Interface for the PositionManager contract in Half-Life protocol
interface IPositionManager {
    /// @notice Struct representing a user position
    struct Position {
        address user;
        bool isLong;
        uint256 amount;
        uint256 leverage;
        uint256 entryIndexValue;
        uint256 entryTimestamp;
        uint256 margin;
        bool isOpen;
    }

    /// @notice Open a new position
    /// @param user The address of the user
    /// @param isLong True for long, false for short
    /// @param amount The position size
    /// @param leverage The leverage used
    /// @param entryIndexValue The index value at entry
    /// @param margin The margin provided
    /// @return positionId The ID of the new position
    function openPosition(
        address user,
        bool isLong,
        uint256 amount,
        uint256 leverage,
        uint256 entryIndexValue,
        uint256 margin
    ) external returns (uint256 positionId);

    /// @notice Close an existing position
    /// @param positionId The ID of the position
    /// @param exitIndexValue The index value at exit
    /// @return pnl The profit or loss from the position
    function closePosition(
        uint256 positionId,
        uint256 exitIndexValue
    ) external returns (int256 pnl);

    /// @notice Get a position by ID
    /// @param positionId The ID of the position
    /// @return position The Position struct
    function getPosition(
        uint256 positionId
    ) external view returns (Position memory position);

    /// @notice Update margin for a position
    /// @param positionId The ID of the position
    /// @param newMargin The new margin amount
    function updateMargin(uint256 positionId, uint256 newMargin) external;

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

    /// @notice Get all open position IDs for a user
    /// @param user The user address
    /// @return positionIds Array of open position IDs
    function getUserOpenPositionIds(
        address user
    ) external view returns (uint256[] memory positionIds);

    /// @notice Get all open position IDs in the system
    /// @return positionIds Array of all open position IDs
    function getAllOpenPositionIds()
        external
        view
        returns (uint256[] memory positionIds);
}
