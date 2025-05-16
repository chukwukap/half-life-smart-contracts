// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

// NOTE: For documentation, use explicit versioned imports in deployment scripts and documentation.
// import {OwnableUpgradeable} from "@openzeppelin/[email protected]/access/OwnableUpgradeable.sol";
// import {PausableUpgradeable} from "@openzeppelin/[email protected]/security/PausableUpgradeable.sol";
// import {Initializable} from "@openzeppelin/[email protected]/proxy/utils/Initializable.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ILiquidationEngine} from "./interfaces/ILiquidationEngine.sol";
import {IPositionManager} from "./interfaces/IPositionManager.sol";

/// @title LiquidationEngine
/// @author Half-Life Protocol
/// @notice Handles position liquidations for the perpetual index market
/// @dev Upgradeable and pausable contract
contract LiquidationEngine is
    ILiquidationEngine,
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable
{
    // --- Constants ---
    uint256 private constant BASIS_POINTS_DENOMINATOR = 10_000;

    // --- Events ---
    event LiquidationPenaltyUpdated(uint256 penaltyBps);
    event PositionLiquidated(
        address indexed user,
        uint256 indexed positionId,
        address indexed market,
        int256 pnl,
        uint256 penalty
    );

    // --- Errors ---
    error NotAuthorized();
    error InvalidInput();
    error PositionNotFound();
    error InsufficientMargin();

    // --- State Variables ---
    address public positionManager;
    uint256 public liquidationPenalty; // in basis points

    /// @notice Initializer for upgradeable contract
    /// @param _positionManager The PositionManager contract address
    function initialize(address _positionManager) external virtual initializer {
        __Ownable_init(msg.sender);
        __Pausable_init();
        positionManager = _positionManager;
    }

    /// @notice Check if a position is eligible for liquidation
    /// @param positionId The ID of the position
    /// @param currentIndexValue The current index value
    /// @param maintenanceMargin The maintenance margin requirement
    /// @return _canLiquidate True if eligible for liquidation
    function canLiquidate(
        uint256 positionId,
        uint256 currentIndexValue,
        uint256 maintenanceMargin
    ) external view override returns (bool _canLiquidate) {
        IPositionManager.Position memory position = IPositionManager(
            positionManager
        ).getPosition(positionId);
        if (!position.isOpen) return false;
        int256 direction = position.isLong ? int256(1) : int256(-1);
        int256 pnl = direction *
            (int256(currentIndexValue) - int256(position.entryIndexValue)) *
            int256(position.amount) *
            int256(position.leverage);
        int256 marginAfterPnL = int256(position.margin) + pnl;
        _canLiquidate = marginAfterPnL < int256(maintenanceMargin);
    }

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
    ) external override whenNotPaused returns (int256 pnl, uint256 penalty) {
        IPositionManager.Position memory position = IPositionManager(
            positionManager
        ).getPosition(positionId);
        if (!position.isOpen) revert PositionNotFound();
        int256 direction = position.isLong ? int256(1) : int256(-1);
        pnl =
            direction *
            (int256(currentIndexValue) - int256(position.entryIndexValue)) *
            int256(position.amount) *
            int256(position.leverage);
        int256 marginAfterPnL = int256(position.margin) + pnl;
        if (marginAfterPnL >= int256(maintenanceMargin))
            revert InsufficientMargin();
        // Calculate penalty as a percentage of remaining margin (if any)
        uint256 penaltyBps = liquidationPenalty;
        uint256 penaltyBase = marginAfterPnL > 0 ? uint256(marginAfterPnL) : 0;
        penalty = (penaltyBase * penaltyBps) / BASIS_POINTS_DENOMINATOR;
        // Close the position in PositionManager (onlyOwner or onlyMarket should be enforced)
        // For demonstration, assume the market contract calls this and is owner
        // In production, use access control modifiers
        // Mark position as closed and emit event
        // (This is a stateless engine, so actual state change is in PositionManager/Market)
        emit PositionLiquidated(
            position.user,
            positionId,
            msg.sender,
            pnl,
            penalty
        );
    }

    /// @notice Get the current liquidation penalty
    /// @return penaltyBps The current liquidation penalty in basis points
    function getLiquidationPenalty() external view returns (uint256) {
        return liquidationPenalty;
    }

    /// @notice Set the liquidation penalty (onlyOwner)
    /// @param penaltyBps The new liquidation penalty in basis points
    function setLiquidationPenalty(uint256 penaltyBps) external onlyOwner {
        if (penaltyBps > BASIS_POINTS_DENOMINATOR) revert InvalidInput();
        liquidationPenalty = penaltyBps;
        emit LiquidationPenaltyUpdated(penaltyBps);
    }
}
