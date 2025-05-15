// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// NOTE: For documentation, use explicit versioned imports in deployment scripts and documentation.
// import {OwnableUpgradeable} from "@openzeppelin/[email protected]/access/OwnableUpgradeable.sol";
// import {PausableUpgradeable} from "@openzeppelin/[email protected]/security/PausableUpgradeable.sol";
// import {ReentrancyGuardUpgradeable} from "@openzeppelin/[email protected]/security/ReentrancyGuardUpgradeable.sol";
// import {Initializable} from "@openzeppelin/[email protected]/proxy/utils/Initializable.sol";

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

    // --- New: Funding, Solvency, and Liquidation for Uniswap v4 Hook Integration ---

    /// @notice Applies funding payment to all open positions for a user
    /// @dev Called by the Uniswap v4 hook before swap; updates margin
    /// @param user The address of the user
    /// @param fundingRate The funding rate to apply (signed integer)
    /// @return totalPayment The total funding payment applied (can be negative)
    function applyFunding(
        address user,
        int256 fundingRate
    ) external whenNotPaused nonReentrant returns (int256 totalPayment) {
        uint256[] memory openIds = this.getUserOpenPositionIds(user);
        totalPayment = 0;
        for (uint256 i = 0; i < openIds.length; i++) {
            Position storage pos = positions[openIds[i]];
            if (!pos.isOpen) continue;
            // Funding payment = fundingRate * amount * leverage
            int256 payment = (fundingRate *
                int256(pos.amount) *
                int256(pos.leverage)) / int256(BASIS_POINTS_DENOMINATOR);
            // Update margin (can be negative)
            if (payment != 0) {
                if (payment < 0 && uint256(-payment) > pos.margin) {
                    pos.margin = 0;
                } else {
                    pos.margin = uint256(int256(pos.margin) + payment);
                }
                emit MarginUpdated(openIds[i], pos.margin);
            }
            totalPayment += payment;
        }
        return totalPayment;
    }

    /// @notice Checks if all open positions for a user are solvent (above maintenance margin)
    /// @dev Used by the Uniswap v4 hook before swap
    /// @param user The address of the user
    /// @return isSolvent True if all positions are solvent
    function isSolvent(address user) external view returns (bool isSolvent) {
        uint256[] memory openIds = this.getUserOpenPositionIds(user);
        isSolvent = true;
        for (uint256 i = 0; i < openIds.length; i++) {
            Position memory pos = positions[openIds[i]];
            if (!pos.isOpen) continue;
            // Assume a global maintenanceMargin (set by owner)
            uint256 maintenanceMargin = maintenanceMarginBps;
            if (pos.margin < maintenanceMargin) {
                isSolvent = false;
                break;
            }
        }
    }

    /// @notice Liquidates all undercollateralized positions for a user
    /// @dev Called by the Uniswap v4 hook before swap
    /// @param user The address of the user
    /// @return totalLoss The total loss from liquidation
    function liquidate(
        address user
    ) external whenNotPaused nonReentrant returns (uint256 totalLoss) {
        uint256[] memory openIds = this.getUserOpenPositionIds(user);
        totalLoss = 0;
        for (uint256 i = 0; i < openIds.length; i++) {
            Position storage pos = positions[openIds[i]];
            if (!pos.isOpen) continue;
            // Assume a global maintenanceMargin (set by owner)
            uint256 maintenanceMargin = maintenanceMarginBps;
            if (pos.margin < maintenanceMargin) {
                totalLoss += pos.margin;
                pos.isOpen = false;
                emit PositionClosed(user, openIds[i], -int256(pos.margin));
            }
        }
        return totalLoss;
    }

    // --- Admin: Set global maintenance margin (basis points) ---
    uint256 public maintenanceMarginBps;
    function setMaintenanceMargin(uint256 marginBps) external onlyOwner {
        maintenanceMarginBps = marginBps;
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
    ) external whenNotPaused nonReentrant returns (uint256 positionId) {
        if (amount == 0 || leverage == 0 || margin == 0) revert InvalidInput();

        positionId = nextPositionId++;
        positions[positionId] = Position({
            user: user,
            isLong: isLong,
            amount: amount,
            leverage: leverage,
            entryIndexValue: indexValue,
            entryTimestamp: block.timestamp,
            margin: margin,
            isOpen: true
        });

        userPositions[user].push(positionId);
        emit PositionOpened(positionId, user, isLong, amount, leverage, margin);
        return positionId;
    }

    /// @notice Close a position
    /// @param positionId The position ID
    /// @param indexValue The current index value
    /// @return pnl The profit or loss from closing
    function closePosition(
        uint256 positionId,
        uint256 indexValue
    ) external whenNotPaused nonReentrant returns (int256 pnl) {
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
    /// @return position The position details
    function getPosition(
        uint256 positionId
    ) external view returns (Position memory position) {
        position = positions[positionId];
        if (!position.isOpen) revert PositionNotFound();
    }

    /// @notice Get all open positions for a user
    /// @param user The user address
    /// @return positionIds Array of position IDs
    function getUserPositions(
        address user
    ) external view returns (uint256[] memory) {
        return userPositions[user];
    }

    /// @dev This function is used to check if a position can be liquidated
    /// @param positionId The position ID
    /// @param indexValue The current index value
    /// @param maintenanceMargin The required maintenance margin
    /// @return _canLiquidate True if the position is eligible for liquidation
    function canLiquidate(
        uint256 positionId,
        uint256 indexValue,
        uint256 maintenanceMargin
    ) external view returns (bool _canLiquidate) {
        Position memory position = positions[positionId];
        if (!position.isOpen) return false;

        int256 direction = position.isLong ? int256(1) : int256(-1);
        int256 pnl = direction *
            (int256(indexValue) - int256(position.entryIndexValue)) *
            int256(position.amount) *
            int256(position.leverage);
        int256 marginAfterPnL = int256(position.margin) + pnl;
        _canLiquidate = marginAfterPnL < int256(maintenanceMargin);
    }

    /// @notice Update the margin of a position
    /// @dev Only callable by the market contract
    /// @param positionId The ID of the position
    /// @param newMargin The new margin value
    function updateMargin(
        uint256 positionId,
        uint256 newMargin
    ) external onlyOwner whenNotPaused {
        Position storage pos = positions[positionId];
        if (!pos.isOpen) revert PositionClosedError();
        pos.margin = newMargin;
        emit MarginUpdated(positionId, newMargin);
    }

    /// @notice Get all open position IDs for a user
    /// @param user The user address
    /// @return positionIds Array of open position IDs
    function getUserOpenPositionIds(
        address user
    ) external view returns (uint256[] memory positionIds) {
        uint256[] memory allUserPositions = userPositions[user];
        uint256 openCount = 0;

        // First count open positions
        for (uint256 i = 0; i < allUserPositions.length; i++) {
            if (positions[allUserPositions[i]].isOpen) {
                openCount++;
            }
        }

        // Then create array with correct size
        positionIds = new uint256[](openCount);
        uint256 currentIndex = 0;

        // Fill array with open position IDs
        for (uint256 i = 0; i < allUserPositions.length; i++) {
            if (positions[allUserPositions[i]].isOpen) {
                positionIds[currentIndex] = allUserPositions[i];
                currentIndex++;
            }
        }
    }

    /// @notice Get all open position IDs in the system
    /// @return positionIds Array of all open position IDs
    function getAllOpenPositionIds()
        external
        view
        returns (uint256[] memory positionIds)
    {
        uint256 openCount = 0;

        // First count open positions
        for (uint256 i = 1; i < nextPositionId; i++) {
            if (positions[i].isOpen) {
                openCount++;
            }
        }

        // Then create array with correct size
        positionIds = new uint256[](openCount);
        uint256 currentIndex = 0;

        // Fill array with open position IDs
        for (uint256 i = 1; i < nextPositionId; i++) {
            if (positions[i].isOpen) {
                positionIds[currentIndex] = i;
                currentIndex++;
            }
        }
    }
}
