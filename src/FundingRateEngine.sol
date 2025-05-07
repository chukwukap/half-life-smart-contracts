// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// NOTE: For documentation, use explicit versioned imports in deployment scripts and documentation.
// import {OwnableUpgradeable} from "@openzeppelin/[email protected]/access/OwnableUpgradeable.sol";
// import {PausableUpgradeable} from "@openzeppelin/[email protected]/security/PausableUpgradeable.sol";
// import {Initializable} from "@openzeppelin/[email protected]/proxy/utils/Initializable.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable@5.0.1/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable@5.0.1/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable@5.0.1/security/PausableUpgradeable.sol";
import {IFundingRateEngine} from "./interfaces/IFundingRateEngine.sol";

/// @title FundingRateEngine
/// @author Half-Life Protocol
/// @notice Calculates and settles funding payments for the perpetual index market
/// @dev Handles funding rate logic and settlement
contract FundingRateEngine is
    IFundingRateEngine,
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable
{
    // --- Constants ---
    uint256 private constant FUNDING_RATE_SCALE = 1e18;
    uint256 private constant BASIS_POINTS_DENOMINATOR = 10_000;

    // --- Events ---
    event FundingRateCalculated(
        int256 fundingRate,
        uint256 marketPrice,
        uint256 indexValue
    );
    event FundingSettled(uint256 timestamp);

    // --- Errors ---
    error NotAuthorized();
    error InvalidInput();

    // --- State Variables ---
    uint256 public lastFundingTimestamp;
    int256 public lastFundingRate;

    /// @notice Initializer for upgradeable contract
    function initialize() external initializer {
        __Ownable_init();
        __Pausable_init();
        lastFundingTimestamp = block.timestamp;
        lastFundingRate = 0;
    }

    /// @notice Calculate the funding rate based on market and index values
    /// @param marketPrice The current market price
    /// @param indexValue The current index value
    /// @return fundingRate The calculated funding rate (scaled by FUNDING_RATE_SCALE)
    function calculateFundingRate(
        uint256 marketPrice,
        uint256 indexValue
    ) external view override returns (int256 fundingRate) {
        if (indexValue == 0) revert InvalidInput();
        // Funding rate = (marketPrice - indexValue) / indexValue * FUNDING_RATE_SCALE
        fundingRate = int256(marketPrice) - int256(indexValue);
        fundingRate =
            (fundingRate * int256(FUNDING_RATE_SCALE)) /
            int256(indexValue);
    }

    /// @notice Settle funding payments (update timestamp and emit event)
    /// @param timestamp The timestamp of settlement
    function settleFunding(uint256 timestamp) external override whenNotPaused {
        lastFundingTimestamp = timestamp;
        emit FundingSettled(timestamp);
    }
}
