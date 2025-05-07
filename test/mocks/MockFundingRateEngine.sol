// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {FundingRateEngine} from "../../src/FundingRateEngine.sol";

/// @title MockFundingRateEngine
/// @notice Mock implementation of FundingRateEngine for testing
contract MockFundingRateEngine is FundingRateEngine {
    /// @notice Initialize the contract
    /// @param initialRate The initial funding rate
    function initialize(uint256 initialRate) external {
        __Ownable_init(msg.sender);
        __Pausable_init();
        lastFundingTimestamp = block.timestamp;
        lastFundingRate = 0;
        fundingMultiplier = initialRate;
    }

    /// @notice Calculate funding rate based on market conditions
    /// @param marketPrice The current market price
    /// @param indexValue The reference index value
    /// @return fundingRate The calculated funding rate
    function calculateFundingRate(
        uint256 marketPrice,
        uint256 indexValue
    ) external view override returns (int256 fundingRate) {
        if (marketPrice == 0 || indexValue == 0) return 0;
        return
            int256((marketPrice - indexValue) * fundingMultiplier) /
            int256(indexValue);
    }

    /// @notice Settle funding payments between longs and shorts
    /// @param timestamp The timestamp for the funding interval
    function settleFunding(uint256 timestamp) external override {
        lastFundingTimestamp = timestamp;
        emit FundingSettled(timestamp);
    }
}
