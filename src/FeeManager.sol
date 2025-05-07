// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// NOTE: For documentation, use explicit versioned imports in deployment scripts and documentation.
// import {OwnableUpgradeable} from "@openzeppelin/[email protected]/access/OwnableUpgradeable.sol";
// import {PausableUpgradeable} from "@openzeppelin/[email protected]/security/PausableUpgradeable.sol";
// import {Initializable} from "@openzeppelin/[email protected]/proxy/utils/Initializable.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable@4.9.3/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable@4.9.3/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable@4.9.3/security/PausableUpgradeable.sol";
import {IFeeManager} from "./interfaces/IFeeManager.sol";

/// @title FeeManager
/// @author Half-Life Protocol
/// @notice Handles fee calculation and collection for the perpetual index market
/// @dev Supports trading and liquidation fees, upgradeable and pausable
contract FeeManager is
    IFeeManager,
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable
{
    // --- Constants ---
    uint256 private constant BASIS_POINTS_DENOMINATOR = 10_000;

    // --- Events ---
    event FeeCollected(address indexed user, uint256 amount, string feeType);
    event FeeRateUpdated(string feeType, uint256 newRate);

    // --- Errors ---
    error NotAuthorized();
    error InvalidInput();

    // --- State Variables ---
    uint256 public tradingFeeRate; // in basis points
    uint256 public liquidationFeeRate; // in basis points
    address public feeRecipient;

    /// @notice Initializer for upgradeable contract
    /// @param _feeRecipient Address to receive collected fees
    /// @param _tradingFeeRate Trading fee rate in basis points
    /// @param _liquidationFeeRate Liquidation fee rate in basis points
    function initialize(
        address _feeRecipient,
        uint256 _tradingFeeRate,
        uint256 _liquidationFeeRate
    ) external initializer {
        __Ownable_init();
        __Pausable_init();
        feeRecipient = _feeRecipient;
        tradingFeeRate = _tradingFeeRate;
        liquidationFeeRate = _liquidationFeeRate;
    }

    /// @notice Calculate trading fee for a given amount
    /// @param amount The trade amount
    /// @return fee The trading fee
    function calculateTradingFee(
        uint256 amount
    ) external view override returns (uint256 fee) {
        fee = (amount * tradingFeeRate) / BASIS_POINTS_DENOMINATOR;
    }

    /// @notice Calculate liquidation fee for a given amount
    /// @param amount The amount subject to liquidation
    /// @return fee The liquidation fee
    function calculateLiquidationFee(
        uint256 amount
    ) external view override returns (uint256 fee) {
        fee = (amount * liquidationFeeRate) / BASIS_POINTS_DENOMINATOR;
    }

    /// @notice Collect a fee from a user
    /// @param user The address paying the fee
    /// @param amount The fee amount
    /// @param feeType The type of fee ("trading" or "liquidation")
    function collectFee(
        address user,
        uint256 amount,
        string memory feeType
    ) external override whenNotPaused {
        // In production, transfer tokens from user to feeRecipient
        emit FeeCollected(user, amount, feeType);
    }

    /// @notice Update the trading fee rate (onlyOwner)
    /// @param newRate The new trading fee rate in basis points
    function updateTradingFeeRate(uint256 newRate) external onlyOwner {
        tradingFeeRate = newRate;
        emit FeeRateUpdated("trading", newRate);
    }

    /// @notice Update the liquidation fee rate (onlyOwner)
    /// @param newRate The new liquidation fee rate in basis points
    function updateLiquidationFeeRate(uint256 newRate) external onlyOwner {
        liquidationFeeRate = newRate;
        emit FeeRateUpdated("liquidation", newRate);
    }
}
