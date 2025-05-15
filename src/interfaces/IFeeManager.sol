// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title IFeeManager
/// @notice Interface for the FeeManager contract in Half-Life protocol
interface IFeeManager {
    /// @notice Emitted when fees are collected
    // event FeeCollected(address indexed user, uint256 amount, string feeType);
    /// @notice Emitted when fees are distributed
    event FeesDistributed(
        uint256 treasuryAmount,
        uint256 insuranceAmount,
        uint256 stakersAmount
    );

    event FeeCollected(address indexed user, uint256 amount, string feeType);
    event FeeRateUpdated(string feeType, uint256 newRate);

    /// @notice Calculate trading fee for a given amount
    /// @param amount The amount to calculate the fee on
    /// @return fee The trading fee amount
    function calculateTradingFee(
        uint256 amount
    ) external view returns (uint256 fee);

    /// @notice Collect a fee from a user
    /// @param user The address of the user
    /// @param amount The fee amount
    /// @param feeType The type of fee (e.g., "trading", "funding", "liquidation")
    function collectFee(
        address user,
        uint256 amount,
        string calldata feeType
    ) external;

    /// @notice Distribute collected fees to treasury, insurance, and stakers
    function distributeFees() external;

    /// @notice Set fee parameters (onlyOwner or market)
    /// @param tradingFeeBps Trading fee in basis points
    /// @param fundingFeeBps Funding fee in basis points
    /// @param liquidationFeeBps Liquidation fee in basis points
    function setFeeParameters(
        uint256 tradingFeeBps,
        uint256 fundingFeeBps,
        uint256 liquidationFeeBps
    ) external;

    /// @notice Get current fee parameters
    /// @return tradingFeeBps Trading fee in basis points
    /// @return fundingFeeBps Funding fee in basis points
    /// @return liquidationFeeBps Liquidation fee in basis points
    function getFeeParameters()
        external
        view
        returns (
            uint256 tradingFeeBps,
            uint256 fundingFeeBps,
            uint256 liquidationFeeBps
        );
}
