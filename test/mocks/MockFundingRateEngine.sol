// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {IFundingRateEngine} from "../../src/interfaces/IFundingRateEngine.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title MockFundingRateEngine
/// @notice Mock implementation of FundingRateEngine for testing
contract MockFundingRateEngine is IFundingRateEngine, Initializable {
    uint256 private _fundingRate;
    uint256 private _lastSettlementTimestamp;
    uint256 private _fundingMultiplier;

    /// @notice Initialize the contract
    /// @param initialRate The initial funding rate
    function initialize(uint256 initialRate) external initializer {
        _fundingRate = initialRate;
        _lastSettlementTimestamp = block.timestamp;
        _fundingMultiplier = initialRate;
    }

    /// @notice Set the funding rate
    /// @param newRate The new funding rate
    function setFundingRate(uint256 newRate) external {
        _fundingRate = newRate;
    }

    /// @notice Calculate funding rate based on market conditions
    /// @param marketPrice The current market price
    /// @param entryPrice The reference entry price
    /// @return fundingRate The calculated funding rate
    function calculateFundingRate(
        uint256 marketPrice,
        uint256 entryPrice
    ) external view override returns (int256 fundingRate) {
        return int256(_fundingRate);
    }

    /// @notice Settle funding payments between longs and shorts
    /// @param timestamp The timestamp for the funding interval
    function settleFunding(uint256 timestamp) external override {
        _lastSettlementTimestamp = timestamp;
    }

    /// @notice Get the last settlement timestamp
    /// @return timestamp The last settlement timestamp
    function getLastSettlementTimestamp() external view returns (uint256) {
        return _lastSettlementTimestamp;
    }

    /// @notice Set the funding multiplier
    /// @param fundingMultiplier The new funding multiplier
    function setFundingMultiplier(uint256 fundingMultiplier) external override {
        _fundingMultiplier = fundingMultiplier;
    }

    /// @notice Get the current funding multiplier
    /// @return multiplier The current funding multiplier
    function getFundingMultiplier() external view override returns (uint256) {
        return _fundingMultiplier;
    }
}
