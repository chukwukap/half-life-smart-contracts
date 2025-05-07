// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// NOTE: For documentation, use explicit versioned imports in deployment scripts and documentation.
// import {OwnableUpgradeable} from "@openzeppelin/[email protected]/access/OwnableUpgradeable.sol";
// import {PausableUpgradeable} from "@openzeppelin/[email protected]/security/PausableUpgradeable.sol";
// import {ReentrancyGuardUpgradeable} from "@openzeppelin/[email protected]/security/ReentrancyGuardUpgradeable.sol";
// import {Initializable} from "@openzeppelin/[email protected]/proxy/utils/Initializable.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable@5.0.1/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable@5.0.1/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable@5.0.1/security/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable@5.0.1/security/ReentrancyGuardUpgradeable.sol";
import {IPositionManager} from "./interfaces/IPositionManager.sol";

/// @title PositionManager
/// @author Half-Life Protocol
/// @notice Manages user positions for the Half-Life perpetual index market
/// @dev Handles position storage, opening, closing, and margin updates
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
        address indexed user,
        uint256 positionId,
        bool isLong,
        uint256 amount,
        uint256 leverage
    );
    event PositionClosed(address indexed user, uint256 positionId, int256 pnl);
    event MarginUpdated(uint256 indexed positionId, uint256 newMargin);

    // --- Errors ---
    error NotAuthorized();
    error InvalidInput();
    error PositionNotFound();
    error PositionClosedError();

    // --- Modifiers ---
    modifier onlyMarket() {
        if (msg.sender != market) revert NotAuthorized();
        _;
    }

    // --- State Variables ---
    address public market;
    uint256 public nextPositionId;
    mapping(uint256 => Position) public positions;
    uint256[] private openPositionIds;
    mapping(address => uint256[]) private userOpenPositions;

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
    /// @param _market Address of the PerpetualIndexMarket
    function initialize(address _market) external initializer {
        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        market = _market;
        nextPositionId = 1;
    }

    /// @notice Open a new position
    /// @dev Only callable by the market contract
    /// @param user The address of the user
    /// @param isLong True for long, false for short
    /// @param amount The position size (in index units)
    /// @param leverage The leverage to use
    /// @param entryIndexValue The index value at entry
    /// @param margin The margin to deposit (in marginToken)
    /// @return positionId The ID of the new position
    function openPosition(
        address user,
        bool isLong,
        uint256 amount,
        uint256 leverage,
        uint256 entryIndexValue,
        uint256 margin
    ) external override onlyMarket whenNotPaused returns (uint256 positionId) {
        if (user == address(0) || amount == 0 || margin == 0)
            revert InvalidInput();
        positionId = nextPositionId++;
        positions[positionId] = Position({
            user: user,
            isLong: isLong,
            amount: amount,
            leverage: leverage,
            entryIndexValue: entryIndexValue,
            margin: margin,
            isOpen: true
        });
        openPositionIds.push(positionId);
        userOpenPositions[user].push(positionId);
        emit PositionOpened(user, positionId, isLong, amount, leverage);
    }

    /// @notice Close an existing position
    /// @dev Only callable by the market contract
    /// @param positionId The ID of the position
    /// @param indexValue The current index value
    /// @return pnl The profit or loss from closing the position
    function closePosition(
        uint256 positionId,
        uint256 indexValue
    ) external override onlyMarket whenNotPaused returns (int256 pnl) {
        Position storage pos = positions[positionId];
        if (!pos.isOpen) revert PositionClosedError();
        int256 direction = pos.isLong ? int256(1) : int256(-1);
        pnl =
            direction *
            (int256(indexValue) - int256(pos.entryIndexValue)) *
            int256(pos.amount) *
            int256(pos.leverage);
        pos.isOpen = false;
        // Remove from openPositionIds and userOpenPositions
        _removeOpenPosition(positionId, pos.user);
        emit PositionClosed(pos.user, positionId, pnl);
    }

    /// @notice Get a position by ID
    /// @param positionId The ID of the position
    /// @return The Position struct
    function getPosition(
        uint256 positionId
    ) external view override returns (Position memory) {
        return positions[positionId];
    }

    /// @notice Update the margin of a position
    /// @dev Only callable by the market contract
    /// @param positionId The ID of the position
    /// @param newMargin The new margin value
    function updateMargin(
        uint256 positionId,
        uint256 newMargin
    ) external override onlyMarket whenNotPaused {
        Position storage pos = positions[positionId];
        if (!pos.isOpen) revert PositionClosedError();
        pos.margin = newMargin;
        emit MarginUpdated(positionId, newMargin);
    }

    /// @notice Get all open position IDs
    /// @return Array of open position IDs
    function getAllOpenPositionIds()
        external
        view
        override
        returns (uint256[] memory)
    {
        return openPositionIds;
    }

    /// @notice Get all open position IDs for a user
    /// @param user The address of the user
    /// @return Array of open position IDs for the user
    function getUserOpenPositionIds(
        address user
    ) external view override returns (uint256[] memory) {
        return userOpenPositions[user];
    }

    // --- Internal Functions ---
    function _removeOpenPosition(uint256 positionId, address user) internal {
        // Remove from openPositionIds
        for (uint256 i = 0; i < openPositionIds.length; i++) {
            if (openPositionIds[i] == positionId) {
                openPositionIds[i] = openPositionIds[
                    openPositionIds.length - 1
                ];
                openPositionIds.pop();
                break;
            }
        }
        // Remove from userOpenPositions
        uint256[] storage userPositions = userOpenPositions[user];
        for (uint256 i = 0; i < userPositions.length; i++) {
            if (userPositions[i] == positionId) {
                userPositions[i] = userPositions[userPositions.length - 1];
                userPositions.pop();
                break;
            }
        }
    }
}
