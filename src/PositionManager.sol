// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {IPositionManager} from "./interfaces/IPositionManager.sol";

/// @title PositionManager
/// @notice Manages user positions for the Half-Life protocol
/// @dev Upgradeable, Ownable, Pausable, ReentrancyGuard. All margin and position logic is handled here.
contract PositionManager is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    IPositionManager
{
    /// @notice Emitted when a new position is opened
    event PositionOpened(
        address indexed user,
        uint256 indexed positionId,
        bool isLong,
        uint256 amount,
        uint256 leverage,
        uint256 entryIndexValue,
        uint256 margin
    );
    /// @notice Emitted when a position is closed
    event PositionClosed(
        address indexed user,
        uint256 indexed positionId,
        int256 pnl,
        uint256 exitIndexValue
    );
    /// @notice Emitted when margin is updated
    event MarginUpdated(uint256 indexed positionId, uint256 newMargin);

    /// @dev Custom errors for gas efficiency
    error NotAuthorized();
    error InvalidInput();
    error PositionNotFound();
    error PositionClosedError();
    error InsufficientMargin();

    /// @notice Position storage
    mapping(uint256 => Position) private positions;
    uint256 private nextPositionId;

    /// @notice Only the market contract can call restricted functions
    address public market;

    modifier onlyMarket() {
        if (msg.sender != market) revert NotAuthorized();
        _;
    }

    /// @notice Initializer for upgradeable contract
    /// @param _market The address of the PerpetualIndexMarket contract
    function initialize(address _market) external initializer {
        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        market = _market;
        nextPositionId = 1;
    }

    /// @inheritdoc IPositionManager
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
            entryTimestamp: block.timestamp,
            margin: margin,
            isOpen: true
        });
        emit PositionOpened(
            user,
            positionId,
            isLong,
            amount,
            leverage,
            entryIndexValue,
            margin
        );
    }

    /// @inheritdoc IPositionManager
    function closePosition(
        uint256 positionId,
        uint256 exitIndexValue
    ) external override onlyMarket whenNotPaused returns (int256 pnl) {
        Position storage pos = positions[positionId];
        if (!pos.isOpen) revert PositionClosedError();
        pos.isOpen = false;
        // Calculate P&L: (Current Index Value - Entry Index Value) * Position Size * Direction
        // Direction: 1 for long, -1 for short
        int256 direction = pos.isLong ? int256(1) : int256(-1);
        pnl =
            direction *
            int256(exitIndexValue) -
            direction *
            int256(pos.entryIndexValue);
        pnl = pnl * int256(pos.amount) * int256(pos.leverage);
        emit PositionClosed(pos.user, positionId, pnl, exitIndexValue);
    }

    /// @inheritdoc IPositionManager
    function getPosition(
        uint256 positionId
    ) external view override returns (Position memory position) {
        position = positions[positionId];
    }

    /// @inheritdoc IPositionManager
    function updateMargin(
        uint256 positionId,
        uint256 newMargin
    ) external override onlyMarket whenNotPaused {
        Position storage pos = positions[positionId];
        if (!pos.isOpen) revert PositionClosedError();
        pos.margin = newMargin;
        emit MarginUpdated(positionId, newMargin);
    }

    /// @inheritdoc IPositionManager
    function canLiquidate(
        uint256 positionId,
        uint256 currentIndexValue,
        uint256 maintenanceMargin
    ) external view override returns (bool canLiquidate_) {
        Position storage pos = positions[positionId];
        if (!pos.isOpen) return false;
        // Calculate unrealized P&L
        int256 direction = pos.isLong ? int256(1) : int256(-1);
        int256 pnl = direction *
            int256(currentIndexValue) -
            direction *
            int256(pos.entryIndexValue);
        pnl = pnl * int256(pos.amount) * int256(pos.leverage);
        // Margin after P&L
        int256 marginAfterPnL = int256(pos.margin) + pnl;
        canLiquidate_ = marginAfterPnL < int256(maintenanceMargin);
    }
}
