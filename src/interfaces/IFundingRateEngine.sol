// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/// @title IFundingRateEngine
/// @notice Interface for the FundingRateEngine contract in Half-Life protocol
interface IFundingRateEngine {
    /// @notice Emitted when funding is settled
    event FundingSettled(uint256 indexed timestamp);

    /// @notice Calculate the current funding rate
    /// @param marketPrice The current market price (index value)
    /// @param indexValue The reference index value
    /// @return fundingRate The calculated funding rate (signed integer, can be positive or negative)
    function calculateFundingRate(
        uint256 marketPrice,
        uint256 indexValue
    ) external view returns (int256 fundingRate);

    /// @notice Settle funding payments between longs and shorts
    /// @param timestamp The timestamp for the funding interval
    function settleFunding(uint256 timestamp) external;

    /// @notice Set funding parameters (onlyOwner or market)
    /// @param fundingMultiplier The multiplier for funding rate calculation
    function setFundingMultiplier(uint256 fundingMultiplier) external;

    /// @notice Get the current funding multiplier
    /// @return fundingMultiplier The funding multiplier
    function getFundingMultiplier()
        external
        view
        returns (uint256 fundingMultiplier);
}
