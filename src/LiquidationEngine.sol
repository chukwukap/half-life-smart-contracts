// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {ILiquidationEngine} from "./interfaces/ILiquidationEngine.sol";
import {IPositionManager} from "./interfaces/IPositionManager.sol";

/// @title LiquidationEngine
/// @notice Handles margin checks and forced closures for the Half-Life protocol
/// @dev Upgradeable, Ownable, Pausable. Integrates with PositionManager for position state.
contract LiquidationEngine is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ILiquidationEngine
{
    /// @dev Custom errors for gas efficiency
    error NotAuthorized();
    error InvalidInput();
    error NotLiquidatable();

    /// @notice The penalty in basis points (1e4 = 100%)
    uint256 private liquidationPenaltyBps;
    /// @notice Only the market contract can call restricted functions
    address public market;
    /// @notice The PositionManager contract
    IPositionManager public positionManager;

    modifier onlyMarket() {
        if (msg.sender != market) revert NotAuthorized();
        _;
    }

    /// @notice Initializer for upgradeable contract
    /// @param _market The address of the PerpetualIndexMarket contract
    /// @param _positionManager The address of the PositionManager contract
    /// @param _penaltyBps The initial liquidation penalty in basis points
    function initialize(
        address _market,
        address _positionManager,
        uint256 _penaltyBps
    ) external initializer {
        __Ownable_init();
        __Pausable_init();
        market = _market;
        positionManager = IPositionManager(_positionManager);
        liquidationPenaltyBps = _penaltyBps;
    }

    /// @inheritdoc ILiquidationEngine
    function canLiquidate(
        uint256 positionId,
        uint256 currentIndexValue,
        uint256 maintenanceMargin
    ) external view override returns (bool canLiquidate_) {
        canLiquidate_ = positionManager.canLiquidate(
            positionId,
            currentIndexValue,
            maintenanceMargin
        );
    }

    /// @inheritdoc ILiquidationEngine
    function liquidate(
        uint256 positionId,
        uint256 currentIndexValue,
        uint256 maintenanceMargin
    )
        external
        override
        onlyMarket
        whenNotPaused
        returns (int256 pnl, uint256 penalty)
    {
        if (
            !positionManager.canLiquidate(
                positionId,
                currentIndexValue,
                maintenanceMargin
            )
        ) revert NotLiquidatable();
        // Close the position and get P&L
        pnl = positionManager.closePosition(positionId, currentIndexValue);
        // Calculate penalty (absolute value of P&L * penaltyBps / 1e4)
        penalty = (uint256(_abs(pnl)) * liquidationPenaltyBps) / 1e4;
        address user = positionManager.getPosition(positionId).user;
        emit PositionLiquidated(user, positionId, msg.sender, pnl, penalty);
    }

    /// @inheritdoc ILiquidationEngine
    function setLiquidationPenalty(
        uint256 penaltyBps
    ) external override onlyOwner {
        liquidationPenaltyBps = penaltyBps;
    }

    /// @inheritdoc ILiquidationEngine
    function getLiquidationPenalty()
        external
        view
        override
        returns (uint256 penaltyBps)
    {
        penaltyBps = liquidationPenaltyBps;
    }

    /// @dev Internal helper to get absolute value of int256
    function _abs(int256 x) internal pure returns (int256) {
        return x >= 0 ? x : -x;
    }
}
