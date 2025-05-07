// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

// NOTE: For documentation, use explicit versioned imports in deployment scripts and documentation.
// import {OwnableUpgradeable} from "@openzeppelin/[email protected]/access/OwnableUpgradeable.sol";
// import {PausableUpgradeable} from "@openzeppelin/[email protected]/security/PausableUpgradeable.sol";
// import {ReentrancyGuardUpgradeable} from "@openzeppelin/[email protected]/security/ReentrancyGuardUpgradeable.sol";
// import {Initializable} from "@openzeppelin/[email protected]/proxy/utils/Initializable.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IPositionManager} from "./interfaces/IPositionManager.sol";

/// @title PositionManager
/// @author Half-Life Protocol
/// @notice Handles position management for the perpetual index market
/// @dev Upgradeable and pausable contract
contract PositionManager is
    IPositionManager,
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    // --- Constants ---
    uint256 private constant BASIS_POINTS_DENOMINATOR = 10_000;

    // --- Events ---
    event PositionOpened(
        uint256 indexed positionId,
        address indexed user,
        bool isLong,
        uint256 amount,
        uint256 leverage,
        uint256 margin
    );
    event PositionClosed(address indexed user, uint256 positionId, int256 pnl);
    event MarginUpdated(uint256 indexed positionId, uint256 newMargin);

    // --- Errors ---
    error NotAuthorized();
    error InvalidInput();
    error PositionNotFound();
    error PositionClosedError();
    error InsufficientMargin();

    // --- State Variables ---
    mapping(uint256 => Position) public positions;
    uint256 public nextPositionId;
    mapping(address => uint256[]) private userPositions;

    /// @notice Position struct
    struct Position {
        address user;
        bool isLong;
        uint256 amount;
        uint256 leverage;
        uint256 entryIndexValue;
        uint256 margin;
        bool isOpen;
    }

    /// @notice Initializer for upgradeable contract
    function initialize() external initializer {
        __Ownable_init(msg.sender);
        __Pausable_init();
        __ReentrancyGuard_init();
        nextPositionId = 1;
    }

    /// @notice Open a new position
    /// @param user The address of the user
    /// @param isLong Whether the position is long
    /// @param amount The position size
    /// @param leverage The leverage to use
    /// @param indexValue The current index value
    /// @param margin The margin to deposit
    function openPosition(
        address user,
        bool isLong,
        uint256 amount,
        uint256 leverage,
        uint256 indexValue,
        uint256 margin
    ) external override whenNotPaused nonReentrant {
        if (amount == 0 || leverage == 0 || margin == 0) revert InvalidInput();

        uint256 positionId = nextPositionId++;
        positions[positionId] = Position({
            user: user,
            isLong: isLong,
            amount: amount,
            leverage: leverage,
            entryIndexValue: indexValue,
            margin: margin,
            isOpen: true
        });

        userPositions[user].push(positionId);
        emit PositionOpened(positionId, user, isLong, amount, leverage, margin);
    }

    /// @notice Close a position
    /// @param positionId The position ID
    /// @param indexValue The current index value
    /// @return pnl The profit or loss from closing
    function closePosition(
        uint256 positionId,
        uint256 indexValue
    ) external override whenNotPaused nonReentrant returns (int256 pnl) {
        Position storage position = positions[positionId];
        if (!position.isOpen) revert PositionNotFound();
        if (msg.sender != position.user) revert NotAuthorized();

        int256 direction = position.isLong ? int256(1) : int256(-1);
        pnl =
            direction *
            (int256(indexValue) - int256(position.entryIndexValue)) *
            int256(position.amount) *
            int256(position.leverage);

        position.isOpen = false;
        emit PositionClosed(position.user, positionId, pnl);
    }

    /// @notice Get a position by ID
    /// @param positionId The position ID
    /// @return The position details
    function getPosition(
        uint256 positionId
    ) external view override returns (Position memory) {
        Position memory position = positions[positionId];
        if (!position.isOpen) revert PositionNotFound();
        return position;
    }

    /// @notice Get all open positions for a user
    /// @param user The user address
    /// @return positionIds Array of position IDs
    function getUserPositions(
        address user
    ) external view override returns (uint256[] memory) {
        return userPositions[user];
    }

    /// @notice Check if a position can be liquidated
    /// @param positionId The position ID
    /// @param indexValue The current index value
    /// @param maintenanceMargin The required maintenance margin
    /// @return canLiquidate True if the position is eligible for liquidation
    function canLiquidate(
        uint256 positionId,
        uint256 indexValue,
        uint256 maintenanceMargin
    ) external view override returns (bool canLiquidate) {
        Position memory position = positions[positionId];
        if (!position.isOpen) return false;

        int256 direction = position.isLong ? int256(1) : int256(-1);
        int256 pnl = direction *
            (int256(indexValue) - int256(position.entryIndexValue)) *
            int256(position.amount) *
            int256(position.leverage);
        int256 marginAfterPnL = int256(position.margin) + pnl;
        canLiquidate = marginAfterPnL < int256(maintenanceMargin);
    }

    /// @notice Update the margin of a position
    /// @dev Only callable by the market contract
    /// @param positionId The ID of the position
    /// @param newMargin The new margin value
    function updateMargin(
        uint256 positionId,
        uint256 newMargin
    ) external override onlyOwner whenNotPaused {
        Position storage pos = positions[positionId];
        if (!pos.isOpen) revert PositionClosedError();
        pos.margin = newMargin;
        emit MarginUpdated(positionId, newMargin);
    }
}
