// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IPerpetualIndexMarket
/// @notice Interface for the PerpetualIndexMarket contract in Half-Life protocol
interface IPerpetualIndexMarket {
    /// @notice Emitted when a new position is opened
    event PositionOpened(
        address indexed user,
        uint256 positionId,
        bool isLong,
        uint256 amount,
        uint256 leverage
    );
    /// @notice Emitted when a position is closed
    event PositionClosed(address indexed user, uint256 positionId, int256 pnl);
    /// @notice Emitted when funding is settled
    event FundingSettled(uint256 indexed timestamp);
    /// @notice Emitted when a position is liquidated
    event PositionLiquidated(
        address indexed user,
        uint256 positionId,
        address liquidator
    );
    /// @notice Emitted when the market is paused or unpaused
    event MarketPaused(address indexed admin);
    event MarketUnpaused(address indexed admin);
    /// @notice Emitted when the index value is updated by the oracle
    event IndexValueUpdated(uint256 newValue, uint256 timestamp);

    /// @notice Open a new position (long or short)
    /// @param isLong True for long, false for short
    /// @param amount The position size (in index units)
    /// @param leverage The leverage to use
    /// @param margin The margin to deposit (in marginToken)
    /// @return positionId The ID of the new position
    function openPosition(
        bool isLong,
        uint256 amount,
        uint256 leverage,
        uint256 margin
    ) external returns (uint256 positionId);

    /// @notice Close an existing position
    /// @param positionId The ID of the position
    function closePosition(uint256 positionId) external;

    /// @notice Settle funding payments between longs and shorts
    function settleFunding() external;

    /// @notice Trigger liquidation of a position if eligible
    /// @param positionId The ID of the position
    function liquidate(uint256 positionId) external;

    /// @notice Update the index value (only callable by oracle)
    /// @param newValue The new index value
    function updateIndexValue(uint256 newValue) external;

    /// @notice Pause the market (onlyOwner)
    function pauseMarket() external;

    /// @notice Unpause the market (onlyOwner)
    function unpauseMarket() external;

    /// @notice Deposit margin to the contract
    /// @param amount The amount to deposit
    function depositMargin(uint256 amount) external;

    /// @notice Withdraw margin from the contract (if tracked)
    /// @param amount The amount to withdraw
    function withdrawMargin(uint256 amount) external;
}
