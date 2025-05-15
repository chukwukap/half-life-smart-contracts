// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

// NOTE: For documentation, use explicit versioned imports in deployment scripts and documentation.
// import {OwnableUpgradeable} from "@openzeppelin/[email protected]/access/OwnableUpgradeable.sol";
// import {PausableUpgradeable} from "@openzeppelin/[email protected]/security/PausableUpgradeable.sol";
// import {Initializable} from "@openzeppelin/[email protected]/proxy/utils/Initializable.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IFundingRateEngine} from "./interfaces/IFundingRateEngine.sol";

/// @title FundingRateEngine
/// @author Half-Life Protocol
/// @notice Handles funding rate calculations and settlements for the perpetual index market
/// @dev Upgradeable and pausable contract
contract FundingRateEngine is
    IFundingRateEngine,
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable
{
    // --- Constants ---
    uint256 private constant BASIS_POINTS_DENOMINATOR = 10_000;
    uint256 private constant FUNDING_RATE_SCALE = 1e18;

    // --- Events ---
    event FundingRateUpdated(int256 newRate);
    event FundingMultiplierUpdated(uint256 newMultiplier);

    // --- Errors ---
    error NotAuthorized();
    error InvalidInput();

    // --- State Variables ---
    uint256 public lastFundingTimestamp;
    int256 public lastFundingRate;
    uint256 public fundingMultiplier; // in basis points

    /// @notice Initializer for upgradeable contract
    function initialize() external initializer {
        __Ownable_init(msg.sender);
        __Pausable_init();
        lastFundingTimestamp = block.timestamp;
        lastFundingRate = 0;
    }

    /// @notice Calculate the current funding rate
    /// @param marketPrice The current market price (index value)
    /// @param indexValue The reference index value
    /// @return fundingRate The calculated funding rate (signed integer, can be positive or negative)
    function calculateFundingRate(
        uint256 marketPrice,
        uint256 indexValue
    ) external view override returns (int256 fundingRate) {
        if (marketPrice == 0 || indexValue == 0) return 0;
        int256 imbalance = int256(marketPrice) - int256(indexValue);
        fundingRate =
            (imbalance * int256(fundingMultiplier)) /
            int256(BASIS_POINTS_DENOMINATOR);
    }

    /// @notice Settle funding payments between longs and shorts
    /// @param timestamp The timestamp for the funding interval
    function settleFunding(uint256 timestamp) external override {
        lastFundingTimestamp = timestamp;
        emit FundingRateUpdated(lastFundingRate); // Professional: emit event for tracking
    }

    /// @notice Update funding rate (onlyOwner)
    /// @param newRate The new funding rate
    function updateFundingRate(int256 newRate) external onlyOwner {
        lastFundingRate = newRate;
        lastFundingTimestamp = block.timestamp;
        emit FundingRateUpdated(newRate);
    }

    /// @notice Get the current funding multiplier
    /// @return The current funding multiplier in basis points
    function getFundingMultiplier() external view override returns (uint256) {
        return fundingMultiplier;
    }

    /// @notice Set the funding multiplier (onlyOwner)
    /// @param newMultiplier The new funding multiplier in basis points
    function setFundingMultiplier(
        uint256 newMultiplier
    ) external override onlyOwner {
        fundingMultiplier = newMultiplier;
        emit FundingMultiplierUpdated(newMultiplier);
    }
}
