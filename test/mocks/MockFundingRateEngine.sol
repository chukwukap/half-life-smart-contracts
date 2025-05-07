// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {FundingRateEngine} from "../../src/FundingRateEngine.sol";

/// @title MockFundingRateEngine
/// @notice Mock implementation of FundingRateEngine for testing
contract MockFundingRateEngine is FundingRateEngine {
    /// @notice Initialize the contract
    /// @param initialRate The initial funding rate
    function initialize(uint256 initialRate) external {
        super.initialize();
        fundingMultiplier = initialRate;
    }
}
