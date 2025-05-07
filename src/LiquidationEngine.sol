// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// NOTE: For documentation, use explicit versioned imports in deployment scripts and documentation.
// import {OwnableUpgradeable} from "@openzeppelin/[email protected]/access/OwnableUpgradeable.sol";
// import {PausableUpgradeable} from "@openzeppelin/[email protected]/security/PausableUpgradeable.sol";
// import {Initializable} from "@openzeppelin/[email protected]/proxy/utils/Initializable.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable@4.9.3/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable@4.9.3/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable@4.9.3/security/PausableUpgradeable.sol";
import {ILiquidationEngine} from "./interfaces/ILiquidationEngine.sol";
import {IPositionManager} from "./interfaces/IPositionManager.sol";

/// @title LiquidationEngine
/// @author Half-Life Protocol
/// @notice Handles liquidation logic for the perpetual index market
/// @dev Checks liquidation eligibility and applies penalties
contract LiquidationEngine is
    ILiquidationEngine,
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable
{
    // --- Constants ---
    uint256 private constant BASIS_POINTS_DENOMINATOR = 10_000;
    uint256 private constant LIQUIDATION_PENALTY_BPS = 500; // 5%

    // --- Events ---
    event PositionLiquidated(
        uint256 indexed positionId,
        address indexed user,
        int256 pnl,
        uint256 penalty
    );

    // --- Errors ---
    error NotAuthorized();
    error InvalidInput();
    error PositionNotFound();

    // --- State Variables ---
    address public positionManager;

    /// @notice Initializer for upgradeable contract
    /// @param _positionManager Address of the PositionManager
    function initialize(address _positionManager) external initializer {
        __Ownable_init();
        __Pausable_init();
        positionManager = _positionManager;
    }

    /// @notice Check if a position can be liquidated
    /// @param positionId The ID of the position
    /// @param indexValue The current index value
    /// @param maintenanceMargin The required maintenance margin
    /// @return canLiquidate True if the position is eligible for liquidation
    function canLiquidate(
        uint256 positionId,
        uint256 indexValue,
        uint256 maintenanceMargin
    ) external view override returns (bool canLiquidate) {
        IPositionManager.Position memory pos = IPositionManager(positionManager)
            .getPosition(positionId);
        if (!pos.isOpen) return false;
        int256 direction = pos.isLong ? int256(1) : int256(-1);
        int256 pnl = direction *
            (int256(indexValue) - int256(pos.entryIndexValue)) *
            int256(pos.amount) *
            int256(pos.leverage);
        int256 marginAfterPnL = int256(pos.margin) + pnl;
        canLiquidate = marginAfterPnL < int256(maintenanceMargin);
    }

    /// @notice Liquidate a position and apply penalty
    /// @param positionId The ID of the position
    /// @param indexValue The current index value
    /// @param maintenanceMargin The required maintenance margin
    /// @return pnl The profit or loss from liquidation
    /// @return penalty The penalty applied
    function liquidate(
        uint256 positionId,
        uint256 indexValue,
        uint256 maintenanceMargin
    ) external override whenNotPaused returns (int256 pnl, uint256 penalty) {
        IPositionManager.Position memory pos = IPositionManager(positionManager)
            .getPosition(positionId);
        if (!pos.isOpen) revert PositionNotFound();
        int256 direction = pos.isLong ? int256(1) : int256(-1);
        pnl =
            direction *
            (int256(indexValue) - int256(pos.entryIndexValue)) *
            int256(pos.amount) *
            int256(pos.leverage);
        int256 marginAfterPnL = int256(pos.margin) + pnl;
        if (marginAfterPnL >= int256(maintenanceMargin)) revert NotAuthorized();
        penalty =
            (pos.margin * LIQUIDATION_PENALTY_BPS) /
            BASIS_POINTS_DENOMINATOR;
        emit PositionLiquidated(positionId, pos.user, pnl, penalty);
    }
}
