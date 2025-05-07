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
abstract contract FundingRateEngine is
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

    /// @notice Calculate funding rate based on market conditions
    /// @param longExposure Total long exposure
    /// @param shortExposure Total short exposure
    /// @return rate The calculated funding rate
    function calculateFundingRate(
        uint256 longExposure,
        uint256 shortExposure
    ) external view returns (int256 rate) {
        if (longExposure == 0 || shortExposure == 0) return 0;

        // Calculate rate based on exposure imbalance
        int256 imbalance = int256(longExposure) - int256(shortExposure);
        rate =
            (imbalance * int256(fundingMultiplier)) /
            int256(BASIS_POINTS_DENOMINATOR);
    }

    /// @notice Settle funding payments for a position
    /// @param positionId The position ID
    /// @param isLong Whether the position is long
    /// @param size The position size
    /// @return payment The funding payment amount (positive for payment, negative for receipt)
    function settleFunding(
        uint256 positionId,
        bool isLong,
        uint256 size
    ) external view returns (int256 payment) {
        // Calculate time elapsed since last funding
        uint256 timeElapsed = block.timestamp - lastFundingTimestamp;
        if (timeElapsed == 0) return 0;

        // Calculate funding payment
        int256 rate = lastFundingRate;
        if (isLong) {
            payment =
                (int256(size) * rate * int256(timeElapsed)) /
                int256(FUNDING_RATE_SCALE);
        } else {
            payment =
                -(int256(size) * rate * int256(timeElapsed)) /
                int256(FUNDING_RATE_SCALE);
        }
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
