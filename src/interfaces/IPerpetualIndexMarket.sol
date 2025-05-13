// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/// @title IPerpetualIndexMarket
/// @notice Interface for the PerpetualIndexMarket contract in Half-Life protocol
interface IPerpetualIndexMarket {
    /// @notice Emitted when a new position is opened
    event PositionOpened(address indexed trader, uint256 size, bool isLong);
    /// @notice Emitted when a position is closed
    event PositionClosed(address indexed trader, uint256 size, bool isLong);
    /// @notice Emitted when funding is settled
    event FundingPaid(address indexed trader, uint256 amount);
    /// @notice Emitted when a position is liquidated
    event PositionLiquidated(address indexed trader, uint256 size, bool isLong);
    /// @notice Emitted when the market is paused or unpaused
    event MarketPaused(address indexed admin);
    event MarketUnpaused(address indexed admin);
    /// @notice Emitted when the index value is updated by the oracle
    event IndexValueUpdated(uint256 newValue, uint256 timestamp);

    /// @notice Open a new position (long or short)
    /// @param size The position size (in index units)
    /// @param isLong True for long, false for short
    function openPosition(uint256 size, bool isLong) external;

    /// @notice Close an existing position
    /// @param size The ID of the position
    function closePosition(uint256 size) external;

    /// @notice Settle funding payments between longs and shorts
    function processFunding() external;

    /// @notice Trigger liquidation of a position if eligible
    /// @param size The ID of the position
    /// @param isLong True for long, false for short
    function liquidate(uint256 size, bool isLong) external;

    /// @notice Update the index value (only callable by oracle)
    /// @param newValue The new index value
    function updateIndexValue(uint256 newValue) external;

    /// @notice Pause the market (onlyOwner)
    function pauseMarket() external;

    /// @notice Unpause the market (onlyOwner)
    function unpauseMarket() external;

    /// @notice Deposit margin to the contract
    function addMargin() external payable;

    /// @notice Withdraw margin from the contract (if tracked)
    /// @param amount The amount to withdraw
    function removeMargin(uint256 amount) external;

    /// @notice Get the position details
    /// @param trader The address of the trader
    /// @return size The position size (in index units)
    /// @return isLong True for long, false for short
    function getPosition(
        address trader
    ) external view returns (uint256 size, bool isLong);

    /// @notice Get the margin balance
    /// @param trader The address of the trader
    /// @return margin The margin balance
    function getMargin(address trader) external view returns (uint256);

    /// @notice Get the funding rate
    /// @return fundingRate The funding rate
    function getFundingRate() external view returns (uint256);

    /// @notice Get the oracle price
    /// @return oraclePrice The oracle price
    function getOraclePrice() external view returns (uint256);
}
